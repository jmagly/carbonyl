"""
screen_inspector.py — Raw screen analysis and coordinate visualization toolkit.

Provides tools for agents to inspect and localize regions of the Carbonyl
terminal screen for targeted click operations.

Usage:
    from automation.screen_inspector import ScreenInspector

    si = ScreenInspector(browser.raw_lines())

    # Print full screen with row/col ruler
    si.print_grid()

    # Mark a specific point (for debugging a click target)
    si.print_grid(marks=[(46, 45)])

    # Highlight a rectangular region
    si.print_grid(regions=[(0, 28, 160, 32)])

    # Find text and mark all occurrences (find_text returns 1-indexed, matching ScreenInspector)
    matches = browser.find_text("Sign In")
    si.print_grid(marks=[(m["col"], m["row"]) for m in matches])

    # Or: click the first occurrence directly
    browser.click_text("Sign In")              # click center of text
    browser.click_at_row("Submit", row=42)     # click on a specific row

    # Get annotated text for an agent to reason about
    annotated = si.annotate(marks=[(46, 45)], context_rows=3)
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Optional


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class Mark:
    """A single coordinate marker."""
    col: int   # 1-indexed
    row: int   # 1-indexed
    label: str = "+"

@dataclass
class Region:
    """A rectangular region to highlight (all 1-indexed, inclusive)."""
    col_start: int
    row_start: int
    col_end: int
    row_end: int
    label: str = ""


# ---------------------------------------------------------------------------
# ScreenInspector
# ---------------------------------------------------------------------------

class ScreenInspector:
    """
    Wraps a raw_lines snapshot and provides coordinate visualization tools.

    raw_lines format: [{"row": int, "text": str}, ...]
    Rows and cols are 1-indexed (matching pyte/terminal convention).
    """

    def __init__(self, raw_lines: list[dict]) -> None:
        # Build a row→text dict; rows are 1-indexed
        self._lines: dict[int, str] = {entry["row"]: entry["text"] for entry in raw_lines}
        self._min_row = min(self._lines) if self._lines else 1
        self._max_row = max(self._lines) if self._lines else 1
        self._max_col = max((len(t) for t in self._lines.values()), default=0)

    # ------------------------------------------------------------------
    # Public helpers
    # ------------------------------------------------------------------

    @property
    def row_count(self) -> int:
        return self._max_row

    @property
    def col_count(self) -> int:
        return self._max_col

    def line(self, row: int) -> str:
        """Return the raw text for a given 1-indexed row ('' if out of range)."""
        return self._lines.get(row, "")

    def text_at(self, col: int, row: int, length: int = 1) -> str:
        """Return the character(s) at a specific 1-indexed coordinate."""
        line = self.line(row)
        c0 = col - 1  # convert to 0-indexed
        return line[c0:c0 + length] if 0 <= c0 < len(line) else ""

    def find(self, text: str) -> list[dict]:
        """
        Search for text across all rows.
        Returns [{"col": N, "row": N, "end_col": N}, ...] (1-indexed).
        """
        results = []
        for row, line in sorted(self._lines.items()):
            start = 0
            while True:
                idx = line.find(text, start)
                if idx == -1:
                    break
                results.append({
                    "col": idx + 1,
                    "row": row,
                    "end_col": idx + len(text),
                    "text": text,
                })
                start = idx + 1
        return results

    # ------------------------------------------------------------------
    # Grid rendering
    # ------------------------------------------------------------------

    def render_grid(
        self,
        marks: Optional[list[tuple[int, int]]] = None,
        regions: Optional[list[tuple[int, int, int, int]]] = None,
        row_range: Optional[tuple[int, int]] = None,
        col_range: Optional[tuple[int, int]] = None,
        ruler_every: int = 10,
        mark_char: str = "●",
    ) -> str:
        """
        Render the screen as text with optional coordinate rulers, marks,
        and region highlights.

        Args:
            marks:       List of (col, row) tuples (1-indexed) to mark with ●.
            regions:     List of (col_start, row_start, col_end, row_end) to bracket.
            row_range:   (first_row, last_row) inclusive to restrict output.
            col_range:   (first_col, last_col) inclusive to restrict output.
            ruler_every: Draw ruler ticks every N columns (default 10).
            mark_char:   Character to overlay at each mark (default ●).

        Returns:
            Multi-line string ready for printing or passing to an LLM.
        """
        # Normalise inputs
        mark_set: set[tuple[int, int]] = set(marks or [])
        region_list = [Region(c1, r1, c2, r2) for c1, r1, c2, r2 in (regions or [])]

        r_start = (row_range[0] if row_range else self._min_row)
        r_end   = (row_range[1] if row_range else self._max_row)
        c_start = (col_range[0] if col_range else 1)
        c_end   = (col_range[1] if col_range else self._max_col)

        lines: list[str] = []

        # --- Column ruler header ---
        lines.append(self._col_ruler(c_start, c_end, ruler_every))

        # --- Content rows ---
        for row in range(r_start, r_end + 1):
            raw = self.line(row)
            # Extend to cover full col range
            raw = raw.ljust(c_end)
            # Slice to col range (0-indexed)
            segment = list(raw[c_start - 1:c_end])

            # Apply region brackets
            for rgn in region_list:
                if rgn.row_start <= row <= rgn.row_end:
                    # Left bracket
                    lc = rgn.col_start - c_start  # 0-indexed within segment
                    rc = rgn.col_end   - c_start
                    if 0 <= lc < len(segment):
                        segment[lc] = "["
                    if 0 <= rc < len(segment):
                        segment[rc] = "]"

            # Apply marks
            for (mc, mr) in mark_set:
                if mr == row:
                    idx = mc - c_start  # 0-indexed within segment
                    if 0 <= idx < len(segment):
                        segment[idx] = mark_char

            line_text = "".join(segment).rstrip()
            # Row label prefix (right-aligned, 4 chars)
            lines.append(f"{row:4d} │{line_text}")

        return "\n".join(lines)

    def print_grid(self, **kwargs) -> None:
        """Print render_grid() output to stdout."""
        print(self.render_grid(**kwargs))

    # ------------------------------------------------------------------
    # Contextual annotation (for LLM consumption)
    # ------------------------------------------------------------------

    def annotate(
        self,
        marks: Optional[list[tuple[int, int]]] = None,
        regions: Optional[list[tuple[int, int, int, int]]] = None,
        context_rows: int = 5,
    ) -> str:
        """
        Return an annotated snippet useful for agent prompts.

        For each mark, shows ±context_rows of surrounding content with the
        mark highlighted. Includes a summary table of all marks.
        """
        marks = marks or []
        regions = regions or []
        parts: list[str] = []

        if marks:
            # Summary table
            parts.append("## Marked Coordinates\n")
            parts.append(f"{'ROW':>4}  {'COL':>4}  TEXT AT MARK")
            parts.append("-" * 40)
            for (col, row) in marks:
                char = self.text_at(col, row, 10).rstrip()
                parts.append(f"{row:4d}  {col:4d}  {char!r}")
            parts.append("")

        # Per-mark context windows
        for i, (col, row) in enumerate(marks):
            r_start = max(self._min_row, row - context_rows)
            r_end   = min(self._max_row, row + context_rows)
            parts.append(f"### Mark {i+1}: ({col}, {row})")
            parts.append(self.render_grid(
                marks=[(col, row)],
                regions=regions,
                row_range=(r_start, r_end),
            ))
            parts.append("")

        if not marks and regions:
            # No marks, just show regions
            for i, (c1, r1, c2, r2) in enumerate(regions):
                parts.append(f"### Region {i+1}: cols {c1}-{c2}, rows {r1}-{r2}")
                parts.append(self.render_grid(
                    regions=[(c1, r1, c2, r2)],
                    row_range=(r1, r2),
                ))
                parts.append("")

        return "\n".join(parts)

    # ------------------------------------------------------------------
    # Dot/crosshair overlay helpers
    # ------------------------------------------------------------------

    def crosshair(self, col: int, row: int, radius: int = 3) -> str:
        """
        Render a small crosshair view centred on (col, row).
        Useful for confirming a click target without printing the whole screen.
        """
        r_start = max(self._min_row, row - radius)
        r_end   = min(self._max_row, row + radius)
        c_start = max(1, col - radius * 4)  # cols are ~4x wider visually
        c_end   = min(self._max_col, col + radius * 4)
        return self.render_grid(
            marks=[(col, row)],
            row_range=(r_start, r_end),
            col_range=(c_start, c_end),
        )

    def dot_map(self, step_col: int = 20, step_row: int = 5) -> str:
        """
        Overlay a regular grid of coordinate markers across the entire screen.
        Useful for calibrating click coordinates — shows labelled dots at
        regular intervals so an agent can triangulate any target position.
        """
        marks = []
        row = self._min_row
        while row <= self._max_row:
            col = step_col
            while col <= max(self._max_col, step_col):
                marks.append((col, row))
                col += step_col
            row += step_row

        # Build ruler + dotted screen
        lines: list[str] = [f"Dot map  step_col={step_col}  step_row={step_row}\n"]
        lines.append(self._col_ruler(1, self._max_col, step_col))
        for row in range(self._min_row, self._max_row + 1):
            raw = self.line(row).ljust(self._max_col)
            segment = list(raw)
            for (mc, mr) in marks:
                if mr == row:
                    idx = mc - 1
                    if 0 <= idx < len(segment):
                        segment[idx] = "·"
            lines.append(f"{row:4d} │{''.join(segment).rstrip()}")
        return "\n".join(lines)

    # ------------------------------------------------------------------
    # Utility: region summary
    # ------------------------------------------------------------------

    def summarise_region(
        self,
        col_start: int,
        row_start: int,
        col_end: int,
        row_end: int,
    ) -> dict:
        """
        Return a dict describing a screen region: bounding box, text content,
        and detected interactive markers (forms, links, buttons).
        """
        lines = []
        for row in range(row_start, row_end + 1):
            raw = self.line(row)
            snippet = raw[col_start - 1:col_end]
            if snippet.strip():
                lines.append({"row": row, "text": snippet})

        full_text = "\n".join(e["text"] for e in lines)

        # Heuristic: detect interactive elements from text patterns
        indicators = []
        if re.search(r"\[[ X]\]", full_text):
            indicators.append("checkbox")
        if re.search(r"<[^>]+>|▌|█|░", full_text):
            indicators.append("input_field")
        if re.search(r"(?i)\b(sign in|submit|continue|next|login|search|apply)\b", full_text):
            indicators.append("button")
        if re.search(r"https?://", full_text):
            indicators.append("url")

        return {
            "col_range": (col_start, col_end),
            "row_range": (row_start, row_end),
            "lines": lines,
            "text": full_text,
            "indicators": indicators,
        }

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _col_ruler(self, c_start: int, c_end: int, every: int) -> str:
        """Build a two-row column ruler (tens digit / ones digit)."""
        width = c_end - c_start + 1
        tens = []
        ones = []
        for i in range(width):
            col = c_start + i
            if col % every == 0:
                label = str(col)
                tens.append(label[-2] if len(label) >= 2 else " ")
                ones.append(label[-1])
            else:
                tens.append(" ")
                ones.append(" ")
        prefix = "     │"  # matches "NNNN │" row prefix
        return prefix + "".join(tens) + "\n" + prefix + "".join(ones)
