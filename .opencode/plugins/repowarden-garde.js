// Garde-fou repowarden pour opencode (écrit par repowarden agents init) :
// chaque outil est soumis à « repowarden garde » avant de s'exécuter. Refus
// (code 2) → erreur rendue à l'agent, avec la commande à lancer. repowarden
// absent ou en panne : rien n'est bloqué.
// Plugins opencode : https://opencode.ai/docs/plugins/ (tool.execute.before)
import { spawnSync } from "node:child_process"

export const RepowardenGarde = async ({ directory }) => ({
  "tool.execute.before": async (input, output) => {
    const r = spawnSync("repowarden", ["garde"], {
      input: JSON.stringify({ tool: input.tool, args: output.args, cwd: directory }),
      encoding: "utf8",
    })
    if (r.status === 2) throw new Error((r.stderr || "").trim())
  },
})
