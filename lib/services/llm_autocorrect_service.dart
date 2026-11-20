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
Kamu adalah sistem autocorrect khusus untuk hasil deteksi huruf bahasa isyarat ASL (Sign Language MNIST, 24 kelas A-Y tanpa J dan Z).
Tugasmu: mengoreksi satu kata hasil deteksi kamera menjadi kata yang valid dalam Bahasa Indonesia atau Bahasa Inggris umum.

ATURAN KEMIRIPAN HURUF (CONFUSION MAP):
1. Prioritas utama dari pola error model:
   - M sering berasal dari N (atau A/S saat kamera gerak)
   - S sering berasal dari M atau A (atau E)
   - W sering berasal dari Y, T, atau V
   - I sering berasal dari Y
   - U sering berasal dari V
   - R sering berasal dari U
   - X atau D sering berasal dari T
2. Kemiripan visual kamera live:
   - Kepalan tangan: A <-> S <-> E <-> M <-> N <-> T
   - Dua jari: U <-> V <-> R <-> K
   - Tiga/empat jari: B <-> W <-> F
   - Melengkung: C <-> O
   - Samping/bawah: G <-> H, P <-> Q

BATASAN KETAT (GUARDRAIL ANTI HALUSINASI):
- Jika kata input sudah merupakan kata valid yang umum (Indonesia/Inggris), kembalikan status "already_valid" dan suggestions [].
- Hanya lakukan koreksi jika kata input bisa berubah menjadi kata valid dengan maksimal 2 substitusi huruf (atau maksimal 40% panjang kata) yang HANYA berasal dari Confusion Map di atas.
- Jika kata terlalu acak atau tidak mirip kata valid mana pun setelah mengikuti Confusion Map (misal "XQZPM"), WAJIB kembalikan status "no_match" dan suggestions [].
- Berikan maksimal 3 saran kata terbaik (huruf kapital semua, tanpa spasi).
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
          .map((e) => e.toString().trim().toUpperCase())
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
