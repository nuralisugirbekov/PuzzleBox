"""Import chapter 1.1 of the supplied 23.pdf. Requires pypdf and python-chess.

Usage: python3 scripts/import_pdf_mates.py /path/to/23.pdf output.json
Stops before writing if any diagram or printed solution fails validation.
Page numbers below are physical PDF pages, counted from 1.
"""
import argparse
import json
import re
from pathlib import Path

import chess
from pypdf import PdfReader

GLYPHS = dict(zip('PONMBARSQLKJponmbarsqlkj', 'PPNNBBRRQQKKppnnbbrrqqkk'))
DIAGRAM = r'(?m)^(\d+)\s*\n' + ''.join(
    fr'{rank}\s*\n([^\n]{{8}})\s*\n' for rank in range(8, 0, -1)
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def import_puzzles(source):
    reader = PdfReader(source)
    answers = {}
    for page in reader.pages[971:977]:
        for match in re.finditer(
            r'(?m)^(\d+)\s+1\s*\.\s*([\s\S]*?)(?=^\d+\s+1\s*\.|\Z)',
            page.extract_text(),
        ):
            answers[int(match[1])] = re.sub(r'\s+', '', match[2]).replace('X', 'x').replace('m', '#')

    records = []
    for page_number in range(16, 67):
        matches = list(re.finditer(DIAGRAM, reader.pages[page_number - 1].extract_text()))
        require(len(matches) == 6, f'Expected six diagrams on page {page_number}')
        for match in matches:
            source_id = int(match[1])
            ranks = []
            for row in match.groups()[1:]:
                rank, empty = '', 0
                for glyph in row:
                    if glyph in '0Z':
                        empty += 1
                    else:
                        if empty:
                            rank += str(empty)
                            empty = 0
                        rank += GLYPHS[glyph]
                ranks.append(rank + (str(empty) if empty else ''))

            # The printed answers establish history-dependent rights not encoded
            # by the diagrams: 305 is O-O#, 306 is axb6# en passant.
            castling = 'K' if source_id == 305 else '-'
            ep = 'b6' if source_id == 306 else '-'
            fen = '/'.join(ranks) + f' w {castling} {ep} 0 1'
            board = chess.Board(fen)
            require(board.is_valid(), f'Invalid position {source_id}: {board.status()}')
            mates = []
            for move in list(board.legal_moves):
                board.push(move)
                if board.is_checkmate():
                    mates.append(move.uci())
                board.pop()
            require(mates, f'No mate in one for {source_id}')
            answer = answers[source_id]
            primary = board.parse_san(answer.split('(')[0]).uci()
            require(primary in mates, f'Printed solution does not mate: {source_id}')
            for alternative in re.findall(r'\(1\.([^()]+)\)', answer):
                require(board.parse_san(alternative).uci() in mates,
                        f'Printed alternative does not mate: {source_id}')
            records.append(dict(
                source_id=source_id, source_page=page_number, fen=fen,
                best=primary, solutions=[primary] + sorted(set(mates) - {primary}),
            ))

    require([r['source_id'] for r in records] == list(range(1, 307)), 'Missing or repeated task numbers')
    require(len({r['fen'] for r in records}) == 306, 'Duplicate positions')
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    records = import_puzzles(args.source)
    args.output.write_text(json.dumps(records, indent=2) + '\n', encoding='utf-8')
    alternatives = sum(len(r['solutions']) > 1 for r in records)
    print(f'Imported {len(records)} valid white-to-move positions; {alternatives} have multiple mates.')


if __name__ == '__main__':
    main()
