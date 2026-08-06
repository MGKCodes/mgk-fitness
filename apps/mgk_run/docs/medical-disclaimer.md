# Medical Disclaimer — Runio

> This wording is surfaced to the user at onboarding, before a plan is
> generated, and is available from settings. Have it reviewed before
> submission.
>
> **Where it is enforced:** `CoachFlow` shows it as a gate before the onboarding
> conversation starts, so nothing is generated until the runner accepts;
> `LegalScreen` keeps it reachable afterwards. The in-app copy lives in
> `lib/src/features/legal/domain/legal_copy.dart` — **change both together**, a
> regression test (`test/legal/legal_copy_test.dart`) fails if they drift.

Runio provides general fitness and training information and generates running
training plans. **It is not medical advice and is not a substitute for
professional medical care.**

- **Consult a physician** before starting any training programme, especially if
  you have a heart condition, injury, are pregnant, or have any medical concern.
- **Stop and seek medical attention** if you experience chest pain, dizziness,
  shortness of breath, or any unusual pain during or after exercise.
- Training plans are generated from the information you provide and general
  principles. They **cannot account for your full medical history** and may not
  be appropriate for you.
- Metrics such as calories and effort are **estimates**, not measurements.
- You are responsible for training within your own limits and for your own
  safety.

By using Runio you acknowledge that you exercise at your own risk and that
MGKCodes Ltd is not liable for injury or health issues arising from use of the
app.
