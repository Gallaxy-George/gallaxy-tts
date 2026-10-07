"""Exercise real worker synthesis offline with the supplied runtime's Python."""
import json
import os
from pathlib import Path
import subprocess
import sys

import soundfile as sf

root = Path(__file__).resolve().parents[1]
folder = root / 'build' / 'app-validation'
folder.mkdir(parents=True, exist_ok=True)
texts = ['Hello.', 'Hello world.', 'The cat sat.',
         'Read along, and follow the punctuation.',
         '“Wait,” she said, “is this working?” Yes—it keeps commas, quotes, and punctuation.\n'
         'A second paragraph should stay synchronized as the playback speed changes.']
requests = [{'id': str(i), 'text': text, 'output_file': str(folder / f'smoke-{i}.wav')}
            for i, text in enumerate(texts)]
result = subprocess.run(
    [sys.executable, str(root / 'Resources' / 'kokoro_worker.py'), '--model-revision',
     'a71e4d38b236d968966a2002c4c895dbd12b1c3c'],
    input='\n'.join(map(json.dumps, requests)) + '\n', text=True, capture_output=True,
    env=dict(os.environ, HF_HUB_OFFLINE='1'), timeout=90,
)
assert result.returncode == 0, result.stderr[-2000:]
responses = [json.loads(line) for line in result.stdout.splitlines()]
assert len(responses) == len(requests) + 1, responses
assert all(r.get('ok') for r in responses[1:]), responses
for request in requests:
    path = Path(request['output_file'])
    data, rate = sf.read(path)
    cues = json.loads(path.with_suffix('.captions.json').read_text())
    assert cues and all(0 <= c['start'] < len(data) / rate for c in cues)
    assert all(a['start'] <= b['start'] for a, b in zip(cues, cues[1:]))
    assert ''.join(c['text'] for c in cues).replace(' ', '') == request['text'].replace(' ', '').replace('\n', '')
    print(request['id'], 'seconds', round(len(data) / rate, 3), 'phrases', len(cues))
print('PASS: five offline Kokoro worker requests, preserved punctuation, valid caption timelines')
