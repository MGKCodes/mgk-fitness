// **Public values**, the same two every copy of both apps carries and this
// site's own JavaScript hands to anybody who opens it: the project's address
// and its publishable key, which only ever acts as the person signed in, or as
// nobody. Written here because a secret never is, and `.env*` stays ignored so
// this folder cannot acquire one. The environment can still point the site
// elsewhere, as a test against a stand-in server does.
export const SUPABASE_URL =
  process.env.NEXT_PUBLIC_SUPABASE_URL ??
  "https://cwpwzxjjhxbkwhrgnasn.supabase.co";
export const PUBLISHABLE_KEY =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
  "sb_publishable_Mp7KWjw14O094SpZPDuOdQ_fvz9YrDz";
