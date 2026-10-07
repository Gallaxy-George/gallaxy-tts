"""Run with the installed Kokoro Python runtime (numpy/soundfile required)."""
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace as Token
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Resources'))
from kokoro_captions import phrase_cues, generate_captioned_audio


class CaptionsTests(unittest.TestCase):
    def test_punctuation_and_untimed_closing_quote(self):
        tokens = [Token(text='“Wait', whitespace='', start_ts=0.1),
                  Token(text=',”', whitespace=' ', start_ts=None),
                  Token(text='she', whitespace=' ', start_ts=0.7),
                  Token(text='said.', whitespace='', start_ts=1.0)]
        cues = phrase_cues(tokens, 2, 2)
        self.assertEqual([c['text'] for c in cues], ['“Wait,”', 'she said.'])
        self.assertEqual([c['start'] for c in cues], [2.1, 2.7])

    def test_sample_offsets_and_written_audio(self):
        import numpy as np
        import soundfile as sf
        results = [Token(audio=np.zeros((1, 24000)), graphemes='First.',
                         tokens=[Token(text='First.', whitespace='', start_ts=0.2)]),
                   Token(audio=np.zeros((1, 12000)), graphemes='Next!',
                         tokens=[Token(text='Next!', whitespace='', start_ts=0.1)])]
        model = Token(sample_rate=24000, _get_pipeline=lambda _: lambda *a, **k: iter(results))
        with tempfile.TemporaryDirectory() as folder:
            wav = Path(folder) / 'sample.wav'
            generate_captioned_audio(model, 'First.\nNext!', wav, 'af_bella', 'a', 1)
            cues = json.loads(wav.with_suffix('.captions.json').read_text())
            self.assertEqual(cues, [{'text': 'First.', 'start': 0.0}, {'text': 'Next!', 'start': 1.0}])
            audio, rate = sf.read(wav)
            self.assertEqual(len(audio), 36000)
            self.assertEqual(rate, 24000)

    def test_missing_timestamps_keep_segment(self):
        self.assertEqual(phrase_cues([Token(text='Hello!', whitespace='', start_ts=None)], 1, 2),
                         [{'text': 'Hello!', 'start': 1}])


if __name__ == '__main__':
    unittest.main()
