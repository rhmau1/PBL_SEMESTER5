"""Offline parity with the independent Dart fixtures, no training or network."""
import json
import sys
import unittest
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'docs/training/j_dan_z'))
from static_training import square_hand_crop, full_image_model_input, fuse_app_scores

class StaticPreprocessingContract(unittest.TestCase):
    def test_pixel_parity_with_dart(self):
        data=json.loads((ROOT/'test/fixtures/static_preprocessing_contract.json').read_text())
        for case in data['cases']:
            h,w=case['height'],case['width']
            y,x=np.mgrid[:h,:w]
            image=np.stack([(13*x+7*y)%256,(5*x+11*y)%256,(3*x+17*y)%256],axis=-1).astype(np.uint8)
            for key,scale,minimum in [('context',1.6,.28),('tight',1.4,.22)]:
                expected=np.frombuffer(bytes.fromhex(case[key+'_hex']),dtype=np.uint8).reshape(28,28,1)
                actual=square_hand_crop(image,case['points'],scale,minimum)
                np.testing.assert_array_equal(actual,expected,err_msg=case['name']+' '+key)
            expected=np.frombuffer(bytes.fromhex(case['full_hex']),dtype=np.uint8).reshape(28,28,1)
            np.testing.assert_array_equal(full_image_model_input(image),expected,err_msg=case['name']+' full')

    def test_confident_crop_disagreement_is_rejected(self):
        context=np.full((1,24),.001);context[0,0]=.977
        tight=np.full((1,24),.001);tight[0,1]=.977
        result=fuse_app_scores(context,tight)
        self.assertLess(float(result.max()),.60)

    def test_confident_full_view_vetoes_recovered_wrong_accept(self):
        context=np.full((2,24),.001);context[:,0]=.977
        full=np.full((2,24),.001);full[:,1]=.977
        result=fuse_app_scores(context,context,full,[True,False])
        self.assertAlmostEqual(float(result[0].max()),.59,places=6)
        self.assertGreater(float(result[1].max()),.9)

if __name__=='__main__':unittest.main()
