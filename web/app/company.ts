/**
 * Who is behind the site, as the public registers have it.
 *
 * A UK company has to say on its website who it is: its registered name, its
 * number, where it is registered and its registered office. These are read
 * from here by both footers and by the privacy notice, so that the three
 * cannot come to disagree.
 *
 * **Each line was checked against its own register on 2 October 2026**, not
 * copied from somewhere that had copied it: the company at Companies House,
 * and the data protection registration on the ICO's register, which gives the
 * same address. If the office moves, Companies House moves first and this
 * follows.
 */
export const company = {
  name: "MGKCodes Ltd",
  number: "17035502",
  registered: "England and Wales",
  office: "96 High Street, Reigate, England, RH2 9AP",
  /** The Information Commissioner's Office's registration of us as a controller. */
  ico: "ZC173549",
  email: "hello@mgkcodes.com",
};

/** The sentence the law asks for, in one piece. */
export const disclosure = `${company.name} is registered in ${company.registered}, company number ${company.number}. Registered office: ${company.office}.`;
