import type { Metadata } from "next";
import { AppPage } from "../app-page";

export const metadata: Metadata = {
  title: { absolute: "Lift · MGKFitness" },
  description: "Lift by MGKFitness: a strength log with a coach of its own. Tracking is free; the coach is a subscription.",
  openGraph: { title: "Lift · MGKFitness", url: "/lift" },
};

export default function LiftPage() {
  return <AppPage app="lift" />;
}
