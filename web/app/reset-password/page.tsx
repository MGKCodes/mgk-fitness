import type { Metadata } from "next";
import { Suspense } from "react";
import { ResetPasswordForm } from "./reset-password-form";

export const metadata: Metadata = {
  title: "Choose a new password",
  description: "Choose a new password for your MGKFitness account.",
  // The address carries the one-time token. Nothing on this page links out,
  // and this makes sure that stays true if something ever does.
  referrer: "no-referrer",
};

// Where "Forgot your password?" ends, in Lift and in Run. One page for both,
// because it is one account.
//
// **The link in the email is what brings people here, not the apps.** The
// recovery template in Supabase (supabase/templates/recovery.html) points at
// this page with `{{ .TokenHash }}`. The apps sign in with PKCE, so a reset
// sent back through them would carry a code only the phone that asked can
// exchange; a token hash can be verified by anybody holding the email, on any
// device. It is verified when the form is sent, not when the page loads, so a
// mail scanner that follows the link does not spend it.
export default function ResetPasswordPage() {
  return (
    <main>
      <p className="eyebrow">MGKFitness</p>
      <h1>Choose a new password</h1>
      <p className="lede">
        For the account you use in Lift and Run. Once it is changed, sign in
        with it in either app.
      </p>
      <Suspense fallback={null}>
        <ResetPasswordForm />
      </Suspense>
    </main>
  );
}
