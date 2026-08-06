import 'plan_shape.dart';

/// "What are you after?" — the question that settles [PlanShape].
///
/// ## Why this lives here and not in the intro
///
/// It used to be the second thing Runio ever asked, in the pre-account intro
/// script. It moved because the answer is only *useful* to a runner who is
/// getting a plan, and a plan is now something they opt into rather than
/// something onboarding assumes (ADR-0019).
///
/// Asking it before sign-up meant carrying the answer across a widget swap that
/// destroys the subtree holding it — `auth_gate.dart` had a field, a callback
/// and a paragraph of explanation existing only for that. Asking it at the
/// front of the plan flow instead means the answer is gathered one screen
/// before the intake that consumes it, and nothing has to survive anything.
///
/// What did **not** change is why these are chips: this is the slot intake
/// settles first (ADR-0011), and five buttons remove the wrong-answer case
/// rather than handling it.
class ShapeOption {
  const ShapeOption({
    required this.shape,
    required this.label,
    required this.detail,
  });

  /// Null for "not sure yet" — a real answer, and the one the model is best
  /// placed to resolve once it can actually talk.
  final PlanShape? shape;

  final String label;
  final String detail;
}

/// The four shapes in the runner's words, plus not knowing.
///
/// Phrased as things a person would say rather than as the names of the shapes.
/// Nobody has ever thought "I am a horizon".
const List<ShapeOption> shapeOptions = <ShapeOption>[
  ShapeOption(
    shape: PlanShape.block,
    label: 'I have a race coming up',
    detail: 'A date to be ready for',
  ),
  ShapeOption(
    shape: PlanShape.horizon,
    label: 'I want to reach a distance',
    detail: 'No race entered yet',
  ),
  ShapeOption(
    shape: PlanShape.rhythm,
    label: 'I want to keep a routine',
    detail: 'Same shape most weeks',
  ),
  ShapeOption(
    shape: PlanShape.log,
    label: 'Just record my runs',
    detail: 'No plan needed',
  ),
  ShapeOption(
    shape: null,
    label: "I'm not sure yet",
    detail: 'We can work it out together',
  ),
];

/// What the coach asks. Uses the name gathered in the intro where there is one,
/// so the plan flow opens as a continuation rather than a fresh interrogation.
String shapeQuestion({String? name}) => name == null
    ? 'Right. What are you after?'
    : 'Right, $name. What are you after?';

/// What the coach says when free text arrives where a choice was expected.
///
/// **Currently unreachable**, and deliberately kept: the step renders chips with
/// no text field, so there is no path by which a runner can answer this one
/// wrong. It is here because the moment anyone adds a "something else" field to
/// this screen it becomes reachable again, and the recovery a runner should get
/// is a re-offer rather than a guess. The alternative — carrying on regardless —
/// is how an app ends up storing "37r41ygdfy13g8fg" as an answer and never
/// mentioning it.
const String shapeUnparsed =
    "I didn't quite catch that. Which of these is closest?";
