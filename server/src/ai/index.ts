import type Anthropic from "@anthropic-ai/sdk";
import { config } from "../config.js";
import type { Overview, WhatWorks } from "../insights.js";
import * as claude from "./claude.js";
import { buildContext } from "./context.js";
import * as demo from "./demo.js";
import type { Ideas, Pretest, PretestInput, Recap, UserProfile } from "./schemas.js";

export { AiRefusal } from "./claude.js";
export type { CoachEvent } from "./claude.js";

export interface AiInput {
  profile: UserProfile;
  overview: Overview;
  works: WhatWorks;
}

export const aiSource = () => (config.ai.enabled ? "claude" : "demo");

export async function recap({ profile, overview, works }: AiInput): Promise<Recap> {
  return config.ai.enabled ? claude.recap(buildContext(profile, overview, works)) : demo.recap(profile, overview, works);
}

export async function ideas({ profile, overview, works }: AiInput, request: string | null): Promise<Ideas> {
  return config.ai.enabled ? claude.ideas(buildContext(profile, overview, works), request) : demo.ideas(profile, overview, works);
}

export async function pretest({ profile, overview, works }: AiInput, input: PretestInput): Promise<Pretest> {
  if (!config.ai.enabled) return demo.pretest(profile, overview, works, input);
  const result = await claude.pretest(buildContext(profile, overview, works), input);
  return { ...result, score: Math.max(0, Math.min(100, Math.round(result.score))) };
}

export async function* coach(
  { profile, overview, works }: AiInput,
  history: Array<{ role: "user" | "assistant"; content: string }>,
  message: string,
): AsyncGenerator<claude.CoachEvent, string> {
  if (config.ai.enabled) {
    const params: Anthropic.Beta.BetaMessageParam[] = history.map((m) => ({ role: m.role, content: m.content }));
    return yield* claude.coach(buildContext(profile, overview, works), params, message);
  }
  const reply = demo.coachReply(overview, works, message);
  for (const word of reply.split(/(?<= )/)) yield { kind: "delta", text: word };
  return reply;
}
