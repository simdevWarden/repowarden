// Garde-fou repowarden pour opencode (plugin global).
// Dans un dépôt géré par repowarden (.repowarden.conf ou .repogarde.conf) :
//  - aucune modification de fichier sur une branche protégée (main, develop…)
//    ni en HEAD détaché : le travail se fait sur la branche du ticket ;
//  - dépôt qui suit ses tickets : modification seulement sur une branche de
//    ticket (type/N-sujet), créée par `repowarden ticket N` ;
//  - jamais `--no-verify` (contourne les hooks), jamais `git add .`/`-A`/`--all`
//    (embarquerait des fichiers non voulus, dont des secrets non ignorés) ;
//  - branche de ticket créée seulement par `repowarden ticket N` (liée au
//    ticket, partie d'une branche d'intégration à jour), commit seulement par
//    `repowarden cc` (contrôles, référence au ticket) : `git commit` et la
//    création manuelle d'une branche type/N-… sont refusés.
// Pourquoi : les consignes écrites ne suffisent pas, un modèle peut les ignorer ;
// ici l'outil refuse l'action et donne la commande à lancer.
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";

const EDITION = new Set(["edit", "write", "patch", "apply_patch", "multiedit"]);

function git(dir, args) {
  try {
    return execFileSync("git", ["-C", dir, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

// Dossier existant le plus proche du chemin visé (un fichier peut être à créer)
function dossierExistant(chemin) {
  let d = chemin;
  while (d && !existsSync(d)) d = dirname(d);
  if (d && existsSync(d) && !statSync(d).isDirectory()) d = dirname(d);
  return d;
}

function configRepowarden(racine) {
  for (const f of [".repowarden.conf", ".repogarde.conf"]) {
    if (existsSync(join(racine, f))) return join(racine, f);
  }
  return "";
}

function reglage(conf, cle) {
  for (const section of ["repowarden", "repogarde"]) {
    try {
      const v = execFileSync("git", ["config", "-f", conf, `${section}.${cle}`], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();
      if (v) return v;
    } catch {}
  }
  return "";
}

function suitLesTickets(racine, conf) {
  const v = reglage(conf, "tickets");
  if (/^(true|oui|yes)$/.test(v)) return true;
  if (/^(false|non|no)$/.test(v)) return false;
  const wf = join(racine, ".github", "workflows");
  if (!existsSync(wf)) return false;
  return readdirSync(wf)
    .filter((f) => /\.ya?ml$/.test(f))
    .some((f) => /uses:.*workflows\/tickets\.ya?ml/.test(readFileSync(join(wf, f), "utf8")));
}

// Racine du dépôt repowarden qui contient ce dossier, ou ""
function racineRepowarden(dossier) {
  const racine = dossier ? git(dossier, ["rev-parse", "--show-toplevel"]) : "";
  return racine && configRepowarden(racine) ? racine : "";
}

// Message de refus, ou "" si la modification est permise
export function verifierEdition(cheminVise) {
  const dossier = dossierExistant(cheminVise);
  if (!dossier) return "";
  const racine = git(dossier, ["rev-parse", "--show-toplevel"]);
  if (!racine) return "";
  const conf = configRepowarden(racine);
  if (!conf) return "";
  const branche = git(racine, ["symbolic-ref", "--short", "-q", "HEAD"]);
  const protegees = (reglage(conf, "protectedBranches") || "main master").split(/\s+/);
  const integration = reglage(conf, "integrationBranch");
  if (integration) protegees.push(integration);
  const suite =
    "Prends d'abord le ticket : `repowarden ticket <n>` (crée sa branche et bascule dessus), " +
    "puis recommence la modification. Pas de ticket : `repowarden ticket nouveau \"<titre>\"`.";
  if (!branche) {
    return `repowarden : modification refusée, HEAD détaché dans ${racine}. ${suite}`;
  }
  if (protegees.includes(branche)) {
    return `repowarden : modification refusée sur la branche protégée « ${branche} » (${racine}). ${suite}`;
  }
  if (suitLesTickets(racine, conf) && !/^[a-z]+\/[0-9]+-/.test(branche)) {
    return `repowarden : modification refusée sur « ${branche} », qui n'est pas la branche d'un ticket (type/N-sujet). ${suite}`;
  }
  return "";
}

// Message de refus pour une commande shell, ou "" ; dossier : où elle s'exécute
export function verifierCommande(commande, dossier) {
  if (/(^|\s)--no-verify(\s|$)/.test(commande) || /\bgit\s+commit\b[^|;&]*\s-n(\s|$)/.test(commande)) {
    return "repowarden : --no-verify interdit, il contourne les contrôles. Corrige ce que les hooks signalent.";
  }
  if (/\bgit\s+add\s+(-A|--all|\.)(\s|$)/.test(commande)) {
    return "repowarden : `git add .`, `-A` et `--all` interdits (fichiers non voulus, secrets non ignorés). Nomme les fichiers du ticket : `git add <fichier> …`.";
  }
  if (!racineRepowarden(dossier)) return "";
  if (/\bgit\s+(switch\s+(-c|-C|--create|--force-create)|checkout\s+-[bB]|branch)\s+(\S+\s+)*[a-z]+\/[0-9]+-/.test(commande)) {
    return "repowarden : branche de ticket créée seulement par `repowarden ticket <n>` (liée au ticket, depuis la branche d'intégration à jour). Pas de ticket : `repowarden ticket nouveau \"<titre>\"`.";
  }
  if (/\bgit\s+commit\b/.test(commande) && !/\bgit\s+commit\s+--amend\s+--no-edit\b/.test(commande)) {
    return "repowarden : commit seulement par `repowarden cc --type <type> --scope <portée> -m \"<description>\" --body \"<pourquoi>\" --refs \"Ticket : #<n>\"` (contrôles et référence au ticket). Seul `git commit --amend --no-edit` reste permis.";
  }
  return "";
}

// Règles appliquées à un appel d'outil ; lève une erreur pour le refuser
// (outil : edit, write, bash… ; entree : ses arguments ; dossier : de la session)
export function controler(outil, entree, dossier) {
  const args = entree || {};
  const base = dossier || process.cwd();
  if (EDITION.has(outil)) {
    const cible = args.filePath || args.path || args.file || "";
    const chemin = cible ? (isAbsolute(cible) ? cible : resolve(base, cible)) : base;
    const refus = verifierEdition(chemin);
    if (refus) throw new Error(refus);
  }
  if (outil === "bash" && typeof args.command === "string") {
    const ou = args.workdir ? resolve(base, args.workdir) : base;
    const refus = verifierCommande(args.command, ou);
    if (refus) throw new Error(refus);
  }
}

// opencode 2 : export par défaut { id, setup(ctx) }, hook ctx.tool.hook("execute.before")
export default {
  id: "repowarden.garde",
  async setup(ctx) {
    const dossier = (ctx && (ctx.directory || ctx.worktree)) || process.cwd();
    await ctx.tool.hook("execute.before", (event) => {
      controler(event.tool, event.input, dossier);
    });
  },
};
