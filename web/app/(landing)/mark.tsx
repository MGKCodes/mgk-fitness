/**
 * An app's mark: two chevrons, the trailing one silver. The proportions are
 * `tool/build_app_icons.py`'s, so this is the icon's mark and not a drawing of
 * it. Run's points right and climbs; Lift's points up.
 */
export function Mark({ app }: { app: "run" | "lift" }) {
  const m = 100;
  const w = 0.61 * m;
  const stroke = 0.09 * m;
  const half = 0.215 * w;
  const lean = 0.2 * w;
  const gap = 0.36 * w;
  const rise = 0.215 * w;
  const c = m / 2;

  const chevrons = [0, 1].map((i) => {
    if (app === "lift") {
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
    app === "lift"
      ? [half * 2 + stroke, gap + lean + stroke]
      : [gap + lean + stroke, rise + half * 2 + stroke];
  const top = app === "lift" ? c - gap / 2 - lean - stroke / 2 : c - height / 2;

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
