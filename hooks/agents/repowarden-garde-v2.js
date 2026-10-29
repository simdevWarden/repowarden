// Garde-fou repowarden pour opencode 2.x (écrit par repowarden agents init) :
// chaque outil est soumis à « repowarden garde » avant de s'exécuter. Refus
// (code 2) → erreur rendue à l'agent, avec la commande à lancer. repowarden
// absent ou en panne : rien n'est bloqué. opencode 1.x : repowarden-garde.js,
// à côté (un module à export par défaut y passerait pour un plugin 2.x).
// Plugins opencode 2.x : export par défaut { id, setup }, crochet
// ctx.tool.hook("execute.before") (outils edit, write, shell…). opencode 1.19
// lit tout export par défaut qui a un id comme un plugin à server() : sans
// lui, « failed to load plugin » à chaque démarrage ; server() ne rend aucun
// crochet, le garde-fou 1.x reste celui de repowarden-garde.js
import { spawnSync } from "node:child_process"

// Soumet l'appel d'outil à repowarden garde ; l'erreur levée par le crochet
// empêche l'outil de s'exécuter et son message est rendu à l'agent
function garde(tool, args, cwd) {
  const r = spawnSync("repowarden", ["garde"], {
    input: JSON.stringify({ tool, args, cwd }),
    encoding: "utf8",
  })
  if (r.status === 2) throw new Error((r.stderr || "").trim())
}

export default {
  id: "repowarden-garde",
  // Sans ctx.tool.hook (opencode 1.x charge aussi ce fichier) : rien
  setup: (ctx) => {
    if (typeof ctx?.tool?.hook !== "function") return
    const dossier = ctx.location?.directory || process.cwd()
    return ctx.tool.hook("execute.before", (appel) => garde(appel.tool, appel.input, dossier))
  },
  server: async () => ({}),
}
