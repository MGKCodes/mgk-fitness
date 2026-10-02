/**
 * A mark of the family: two chevrons, the trailing one silver. Run's points
 * right and climbs, Lift's points up, and the suite's heads between the two.
 *
 * The apps' proportions are `tool/build_app_icons.py`'s and the suite's are
 * `web/tool/icon.py`'s, so each is its icon's mark and not a drawing of it.
 */
export function Mark({ of }: { of: "run" | "lift" | "suite" }) {
  const m = 100;
  const w = 0.61 * m;
  const stroke = 0.09 * m;
  const half = 0.215 * w;
  const lean = 0.2 * w;
  const gap = 0.36 * w;
  const rise = 0.215 * w;
  const c = m / 2;
  // The suite's mark is drawn on a grid of half its stroke: each arm four
  // long, the trailing chevron four back and four down.
  const u = stroke / 2;

  const chevrons = [0, 1].map((i) => {
    if (of === "suite") {
      const x = c - 4 * u + i * 4 * u;
      const y = c - i * 4 * u;
      return `${x},${y} ${x + 4 * u},${y} ${x + 4 * u},${y + 4 * u}`;
    }
    if (of === "lift") {
      const x = c - half;
      const y = c + gap / 2 - i * gap;
      return `${x},${y} ${x + half},${y - lean} ${x + half * 2},${y}`;
    }
    const x = c - gap / 2 - lean / 2 + i * gap;
    const y = c + rise / 2 - i * rise;
    return `${x},${y - half} ${x + lean},${y} ${x},${y + half}`;
  });

  // The icon sits the mark in 61% of its tile. Beside a word that padding is
  // dead space, so the view is cropped to the ink.
  const [width, height] =
    of === "suite"
      ? [10 * u, 10 * u]
      : of === "lift"
        ? [half * 2 + stroke, gap + lean + stroke]
        : [gap + lean + stroke, rise + half * 2 + stroke];
  const top = of === "lift" ? c - gap / 2 - lean - stroke / 2 : c - height / 2;

  return (
    <svg
      className="mark"
      viewBox={`${c - width / 2} ${top} ${width} ${height}`}
      aria-hidden="true"
    >
      {chevrons.map((points, i) => (
        <polyline
          key={i}
          points={points}
          fill="none"
          stroke={i === 0 ? "var(--silver)" : "var(--white)"}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      ))}
    </svg>
  );
}
