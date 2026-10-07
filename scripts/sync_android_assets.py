"""Copy iOS translations and validated chess positions to Android assets.
Requires python-chess to export every legal first move for each static puzzle.
Run from the repository root after updating the iOS assets.
"""
import json
import re
from pathlib import Path
import chess

root = Path(__file__).resolve().parents[1]
assets = root / 'android/app/src/main/assets'
assets.mkdir(parents=True, exist_ok=True)
translations = {}
for path in (root / 'PuzzleBoxApp').glob('*.lproj/Localizable.strings'):
    pairs = re.findall(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', path.read_text())
    translations[path.parent.stem] = {
        json.loads('"' + k + '"'): json.loads('"' + v + '"') for k, v in pairs
    }
(assets / 'translations.json').write_text(json.dumps(translations, ensure_ascii=False, indent=2) + '\n')
puzzles = json.loads((root / 'PuzzleBoxApp/Resources/MateInOne.json').read_text())
for puzzle in puzzles:
    board = chess.Board(puzzle['fen'])
    if not board.is_valid() or board.turn != chess.WHITE:
        raise ValueError(f"Invalid puzzle {puzzle['source_id']}")
    legal = list(board.legal_moves)
    mates = []
    for move in legal:
        board.push(move)
        if board.is_checkmate():
            mates.append(move.uci())
        board.pop()
    if set(mates) != set(puzzle['solutions']):
        raise ValueError(f"Incorrect solutions {puzzle['source_id']}")
    puzzle['legal_moves'] = [move.uci() for move in legal]
(assets / 'mates.json').write_text(json.dumps(puzzles, indent=2) + '\n')
print(f'Exported {len(puzzles)} chess positions and {len(translations)} languages.')
