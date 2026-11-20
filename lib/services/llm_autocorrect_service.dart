import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

enum AutocorrectStatus { corrected, alreadyValid, noMatch }

class AutocorrectResult {
  const AutocorrectResult({
    required this.status,
    required this.original,
    this.suggestions = const [],
  });

  factory AutocorrectResult.noMatch(String original) =>
      AutocorrectResult(status: AutocorrectStatus.noMatch, original: original);

  final AutocorrectStatus status;
  final String original;
  final List<String> suggestions;

  bool get hasSuggestions =>
      status == AutocorrectStatus.corrected && suggestions.isNotEmpty;
}

class LlmAutocorrectService {
  LlmAutocorrectService._();

  static final LlmAutocorrectService instance = LlmAutocorrectService._();

  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _model = 'gemini-3.5-flash-lite';
  static const Duration _timeout = Duration(seconds: 4);

  final Map<String, AutocorrectResult> _cache = {};

  static const String _systemPrompt = '''
Kamu adalah sistem pemisah kata (spasi) dan autocorrect untuk hasil deteksi huruf bahasa isyarat ASL (24 kelas A-Y tanpa J dan Z).
Input dari pengguna adalah 1 kata ATAU 1 kalimat pendek yang seluruh hurufnya digabung TANPA SPASI, dan mungkin mengandung salah deteksi huruf.

TUGASMU:
1. Pisahkan deretan huruf tanpa spasi menjadi kata-kata yang bermakna dengan spasi (prioritaskan Bahasa Indonesia baku sesuai KBBI, atau Bahasa Inggris umum jika memang kalimat Inggris).
2. Koreksi huruf yang salah deteksi HANYA menggunakan aturan Confusion Map di bawah ini.

ATURAN KEMIRIPAN HURUF (CONFUSION MAP):
- M <-> N <-> E <-> S <-> A <-> T (kepalan tangan tertutup; contoh: E sering berasal dari M, S sering berasal dari A atau M)
- U <-> V <-> R <-> K
- Y -> W atau I (Y TIDAK PERNAH menjadi B atau huruf lain)
- T -> X, D, atau W
- B <-> W <-> F
- C <-> O
- G <-> H
- P <-> Q

ATURAN KERAS (GUARDRAIL):
1. DILARANG mengubah huruf ke huruf lain di luar Confusion Map di atas.
2. Setiap kata hasil pemisahan dan koreksi WAJIB berupa kata nyata yang baku di KBBI atau kamus Inggris (contoh: SAYAMAKANBAYAE -> SAYA MAKAN BAYAM).
3. Batas koreksi: maksimal 1-2 huruf per kata (atau maksimal 30% dari total panjang input) yang boleh diganti sesuai Confusion Map.
4. Jika input adalah 1 kata tunggal yang sudah valid tanpa perlu spasi maupun koreksi (misal "BAYAM" atau "BALI"), kembalikan status "already_valid" dan suggestions [].
5. Jika input berupa gabungan kata yang hanya butuh dipisah spasi atau dikoreksi hurufnya, kembalikan status "corrected" dengan maksimal 3 saran terbaik (huruf kapital semua, dipisah spasi).
6. Jika deretan huruf terlalu acak dan tidak bisa membentuk kata/kalimat yang masuk akal setelah mengikuti Confusion Map (misal "XQZPMK"), WAJIB kembalikan status "no_match" dan suggestions [].
''';

  Future<AutocorrectResult> correctWord(String rawSequence) async {
    final normalized = rawSequence.trim().toUpperCase();

    // Lapis 1: Pre-filter lokal sebelum memanggil API
    if (normalized.length < 2 || !RegExp(r'^[A-Z]+$').hasMatch(normalized)) {
      return AutocorrectResult.noMatch(normalized);
    }

    if (_cache.containsKey(normalized)) {
      return _cache[normalized]!;
    }

    if (_apiKey.isEmpty) {
      return AutocorrectResult.noMatch(normalized);
    }

    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$_model:generateContent?key=$_apiKey',
      );

      final request = await client.postUrl(uri).timeout(_timeout);
      request.headers.contentType = ContentType.json;

      final payload = {
        'systemInstruction': {
          'parts': [
            {'text': _systemPrompt},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': 'Koreksi hasil deteksi huruf ini: "$normalized"'},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.0,
          'responseMimeType': 'application/json',
          'responseSchema': {
            'type': 'OBJECT',
            'properties': {
              'status': {
                'type': 'STRING',
                'enum': ['corrected', 'already_valid', 'no_match'],
              },
              'suggestions': {
                'type': 'ARRAY',
                'items': {'type': 'STRING'},
              },
            },
            'required': ['status', 'suggestions'],
          },
        },
      };

      request.add(utf8.encode(jsonEncode(payload)));

      final response = await request.close().timeout(_timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('Gemini error ${response.statusCode}: $body');
        return AutocorrectResult.noMatch(normalized);
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        return AutocorrectResult.noMatch(normalized);
      }

      final parts =
          (candidates.first as Map<String, dynamic>)['content']?['parts']
              as List<dynamic>?;
      final jsonText = parts?.firstOrNull?['text'] as String?;
      if (jsonText == null || jsonText.isEmpty) {
        return AutocorrectResult.noMatch(normalized);
      }

      final resultMap = jsonDecode(jsonText) as Map<String, dynamic>;
      final rawStatus = resultMap['status'] as String? ?? 'no_match';
      final rawSuggestions = (resultMap['suggestions'] as List<dynamic>? ?? [])
          .map(
            (e) => e
                .toString()
                .trim()
                .replaceAll(RegExp(r'\s+'), ' ')
                .toUpperCase(),
          )
          .where((e) => e.isNotEmpty && e != normalized)
          .toSet()
          .take(3)
          .toList(growable: false);

      final status = switch (rawStatus) {
        'corrected' when rawSuggestions.isNotEmpty =>
          AutocorrectStatus.corrected,
        'already_valid' => AutocorrectStatus.alreadyValid,
        _ => AutocorrectStatus.noMatch,
      };

      final result = AutocorrectResult(
        status: status,
        original: normalized,
        suggestions: status == AutocorrectStatus.corrected
            ? rawSuggestions
            : const [],
      );

      _cache[normalized] = result;
      return result;
    } on TimeoutException {
      return AutocorrectResult.noMatch(normalized);
    } on SocketException {
      return AutocorrectResult.noMatch(normalized);
    } catch (_) {
      return AutocorrectResult.noMatch(normalized);
    } finally {
      client.close(force: true);
    }
  }

  void clearCache() => _cache.clear();
}
