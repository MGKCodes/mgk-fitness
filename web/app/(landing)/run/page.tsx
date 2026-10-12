import type { Metadata } from "next";
import { AppPage } from "../app-page";

export const metadata: Metadata = {
  title: { absolute: "Run · MGKFitness" },
  description: "Run by MGKFitness: a running tracker and training coach. Tracking is free; the coach is a subscription.",
  openGraph: { title: "Run · MGKFitness", url: "/run" },
};

export default function RunPage() {
  return <AppPage app="run" />;
}
