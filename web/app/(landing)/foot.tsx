import { company, disclosure } from "../company";
import { help } from "./content";
import { social, source } from "./links";

const instagram = social.find((account) => account.name === "Instagram" && account.url);

/** The foot of every page: each app's help and legal pages, and the suite's. */
export function Foot() {
  return (
    <footer className="foot">
      <nav aria-label="Run">
        <h3>
          <a href="/run">Run</a>
        </h3>
        {help.run.map(([label, href]) => (
          <a key={href} href={href}>
            {label}
          </a>
        ))}
      </nav>
      <nav aria-label="Lift">
        <h3>
          <a href="/lift">Lift</a>
        </h3>
        {help.lift.map(([label, href]) => (
          <a key={href} href={href}>
            {label}
          </a>
        ))}
      </nav>
      <nav aria-label="MGKFitness">
        <h3>MGKFitness</h3>
        <a href="/open-source">Open source</a>
        <a href="/privacy">Privacy on this website</a>
        {instagram && (
          <a href={instagram.url} target="_blank" rel="noopener">
            Instagram
          </a>
        )}
        {source.open && <a href={source.repository}>Source on GitHub</a>}
        <p>
          Made by {company.name}. <a href={`mailto:${company.email}`}>{company.email}</a>
        </p>
      </nav>
      <p className="registered">{disclosure}</p>
    </footer>
  );
}
