#!/usr/bin/env python3
"""Exercise generation against disposable local Git sources."""
from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    'solo5': ['opam/solo5.opam'],
    'ocaml-solo5': ['ocaml-solo5.opam'],
    'mirage': ['mirage.opam', 'mirage-runtime.opam'],
    'ocaml-gmp': ['gmp.opam'],
    'mirage-crypto': [f'{name}.opam' for name in ('mirage-crypto', 'mirage-crypto-rng', 'mirage-crypto-rng-mirage', 'mirage-crypto-rng-mkernel', 'mirage-crypto-pk', 'mirage-crypto-ec')],
}

def digest(root):
    return hashlib.sha256(b''.join(str(p.relative_to(root)).encode() + p.read_bytes()
                                  for p in sorted(root.rglob('opam')))).hexdigest()

with tempfile.TemporaryDirectory(prefix='overlay-test-') as tmp:
    root = Path(tmp)
    overlay = root / 'overlay'
    overlay.mkdir()
    shutil.copy(ROOT / 'generate.sh', overlay)
    for name, files in SOURCES.items():
        repo = root / name
        repo.mkdir()
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        for file in files:
            path = repo / file
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('opam-version: "2.0"\nversion: "upstream"\nsynopsis: "committed metadata"\n')
        subprocess.run(['git', '-C', str(repo), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'source'], check=True)
    env = dict(os.environ, FORKS_DIR=str(root))
    env.pop('FORKS_URL', None)
    def generate():
        return subprocess.run(['sh', str(overlay / 'generate.sh')], env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=10)
    result = generate()
    assert result.returncode == 0, result.stdout
    packages = overlay / 'packages'
    opams = sorted(packages.rglob('opam'))
    assert len(opams) == 11, len(opams)
    for opam in opams:
        text = opam.read_text()
        assert 'src: "git+https://github.com/rococompute/' in text, text
        assert 'file://' not in text and str(root) not in text, text
        assert 'version:' not in text.replace('opam-version:', ''), text
    before = digest(packages)
    (root / 'mirage/mirage.opam').write_text('uncommitted metadata that must not enter overlay\n')
    result = generate()
    assert result.returncode == 0, result.stdout
    assert digest(packages) == before, 'metadata did not match pinned commit'
    # A missing checkout must fail before replacing the existing overlay.
    shutil.rmtree(root / 'ocaml-solo5')
    result = generate()
    assert result.returncode != 0, result.stdout
    assert digest(packages) == before, 'failed generation damaged existing packages'
    assert not list(overlay.glob('.generate.*')), 'staging directory leaked'
    print('portable URLs, exact committed metadata, repeatability, and failure preservation passed')
