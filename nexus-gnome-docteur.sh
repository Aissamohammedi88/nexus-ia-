#!/usr/bin/env bash
# ============================================================
#  NEXUS GNOME DOCTEUR
#  Diagnostic + réparation du démarrage automatique GNOME.
#
#  POURQUOI CE SCRIPT : ton TERMINAL lit ~/.bashrc, mais GNOME NON.
#  Si OLLAMA_MODELES est déclaré dans ~/.bashrc, le serveur lancé
#  par GNOME démarre SANS le bon dossier -> ton modèle nexus-axiom-ai
#  devient invisible : "ça marche dans mon terminal mais pas chez GNOME".
#
#  LÉGER : aucun modèle n'est chargé en RAM et le GPU n'est jamais
#  utilisé pendant le diagnostic (on ne lit que des fichiers et
#  l'API /api/show, qui ne charge PAS les poids du modèle).
#
#  Usage :
#     bash nexus-gnome-docteur.sh        -> diagnostic + réparation
#     bash nexus-gnome-docteur.sh --log  -> diagnostic seul (ne modifie rien)
#
#  Journaux :
#     ~/logs/nexus-docteur.log     : le rapport complet
#     ~/logs/ollama.log            : la vie du serveur
#     ~/logs/nexus-env-gnome.txt   : l'environnement exact vu par GNOME
# ============================================================
set -u

ROUGE='\033[0;31m'; VERT='\033[0;32m'; JAUNE='\033[1;33m'; BLEU='\033[0;34m'; NORMAL='\033[0m'

export PATH="/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$PATH"

MODE_DIAG_SEUL=0
[[ "${1:-}" == "--log" ]] && MODE_DIAG_SEUL=1

mkdir -p "$HOME/logs" "$HOME/.config/autostart" "$HOME/.local/bin"
RAPPORT="$HOME/logs/nexus-docteur.log"
: > "$RAPPORT"

NB_OK=0; NB_KO=0
etape() { echo -e "\n${BLEU}==> $1${NORMAL}";            echo ""        >> "$RAPPORT"; echo "==> $1" >> "$RAPPORT"; }
ok()    { echo -e "${VERT}[OK]${NORMAL} $1"; NB_OK=$((NB_OK+1));  echo "[OK] $1" >> "$RAPPORT"; }
ko()    { echo -e "${ROUGE}[KO]${NORMAL} $1"; NB_KO=$((NB_KO+1));  echo "[KO] $1" >> "$RAPPORT"; }
info()  { echo -e "${JAUNE}[..]${NORMAL} $1";                    echo "[..] $1" >> "$RAPPORT"; }

WRAPPER="$HOME/.local/bin/nexus-serve.sh"
DESKTOP="$HOME/.config/autostart/ollama-nexus.desktop"
URL_TAGS="http://127.0.0.1:11434/api/tags"
URL_SHOW="http://127.0.0.1:11434/api/show"

if [[ "$MODE_DIAG_SEUL" == "1" ]]; then
    info "MODE DIAGNOSTIC SEUL : rien ne sera modifié (--log)"
fi

echo "NEXUS GNOME DOCTEUR - $(date)" >> "$RAPPORT"

# ------------------------------------------------------------
etape "1/8 - Ollama est-il installé et où ?"
if command -v ollama >/dev/null 2>&1; then
    ok "Ollama trouvé : $(command -v ollama)"
else
    ko "Ollama introuvable dans le PATH"
    ko "Solution : relance d'abord  bash nexus-tout-en-un.sh"
    echo -e "\nRapport complet : $RAPPORT"
    exit 1
fi

# ------------------------------------------------------------
etape "2/8 - Carte graphique (GPU) ?"
GPU="aucun"
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    GPU="NVIDIA (CUDA)"
elif [[ -e /dev/kfd ]]; then
    GPU="AMD (ROCm)"
fi
FORCER_CPU=0
if [[ "$GPU" == "aucun" ]]; then
    FORCER_CPU=1
    ok "Aucun GPU détecté -> le lanceur forcera le mode CPU (c'est bien, pas de surprise)"
else
    info "GPU détecté : $GPU -> on ne force pas le CPU"
fi

# ------------------------------------------------------------
etape "3/8 - RAM et disque (information)"
if command -v free >/dev/null 2>&1; then
    RAM_MO=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    if [[ -n "${RAM_MO:-}" ]]; then
        info "RAM totale : ${RAM_MO} Mo"
        if [[ "$RAM_MO" -lt 3000 ]]; then
            info "RAM très juste pour un modèle 3B -> mode économe activé dans le lanceur (1 modèle, déchargé après 5 min)"
            info "Si ça rame vraiment : reconstruis avec le squelette léger qwen2.5:1.5b (Modelfile.lite)"
        elif [[ "$RAM_MO" -lt 5000 ]]; then
            info "RAM juste mais OK pour qwen2.5:3b quantisé (environ 2,3 Go chargé)"
            info "Mode économe activé dans le lanceur : 1 seul modèle, déchargé après 5 min d'inactivité"
        else
            ok "RAM suffisante pour qwen2.5:3b (environ 2,3 Go chargé)"
        fi
    fi
fi
DISPO=$(df -h "$HOME" 2>/dev/null | tail -1 | awk '{print $4}')
[[ -n "$DISPO" ]] && info "Espace libre dans ton dossier perso : $DISPO"

# ------------------------------------------------------------
etape "4/8 - Où vit le modèle nexus-axiom-ai sur le disque ?"
MODELES=""
CAUSE_EXPLIQUEE=""
detecter_modeles() {
    local cands=() v d f
    # a) variable déjà dans l'environnement actuel (ton terminal)
    [[ -n "${OLLAMA_MODELES:-}" ]] && cands+=("${OLLAMA_MODELES}")
    # b) déclarée dans les fichiers de config du shell -> LUE PAR LE TERMINAL, PAS PAR GNOME
    while IFS= read -r v; do
        [[ -n "$v" ]] && cands+=("$v")
        CAUSE_EXPLIQUEE="OLLAMA_MODELES est déclaré dans un fichier de config du shell (~/.bashrc ou ~/.profile). Ton terminal le lit, GNOME NON : c'est la cause classique du 'ça marche chez moi mais pas au démarrage'."
    done < <(grep -hE '^[[:space:]]*(export[[:space:]]+)?OLLAMA_MODELES=' \
                 "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" 2>/dev/null \
             | sed -E "s/^[^=]*=[[:space:]]*//" | sed -E "s/[\"']//g" \
             | sed -E "s#\\\$HOME#$HOME#g; s#\\\$\\{HOME\\}#$HOME#g; s#^~#$HOME#")
    # c) emplacements classiques
    cands+=("$HOME/.ollama/models" "/usr/share/ollama/.ollama/models" "$HOME/models" "$HOME/nexus/models")
    local secours=""
    for d in "${cands[@]}"; do
        [[ -d "$d" ]] || continue
        if find "$d/manifests" -type f 2>/dev/null | grep -q 'nexus-axiom-ai'; then
            MODELES="$d"; return 0
        fi
        if [[ -z "$secours" ]] && find "$d/manifests" -type f 2>/dev/null | grep -q 'nexus-deepseek'; then
            secours="$d"
        fi
    done
    [[ -n "$secours" ]] && { MODELES="$secours"; return 0; }
    return 1
}
if detecter_modeles; then
    ok "Dossier des modèles trouvé : $MODELES"
    [[ -n "$CAUSE_EXPLIQUEE" ]] && info "$CAUSE_EXPLIQUEE"
else
    ko "Aucun dossier contenant nexus-axiom-ai ou nexus-deepseek-7b n'a été trouvé"
    ko "Solution : relance  bash nexus-tout-en-un.sh  (il reconstruit le modèle)"
fi

# ------------------------------------------------------------
etape "5/8 - Environnement exact vu par GNOME (capture)"
if [[ -f "$HOME/logs/nexus-env-gnome.txt" ]]; then
    DATE_CAPTURE=$(stat -c '%y' "$HOME/logs/nexus-env-gnome.txt" 2>/dev/null | cut -d. -f1)
    PATH_GNOME=$(grep -m1 '^PATH=' "$HOME/logs/nexus-env-gnome.txt" 2>/dev/null | cut -c1-80)
    ok "Capture GNOME présente ($DATE_CAPTURE)"
    info "PATH vu par GNOME (tronqué) : $PATH_GNOME..."
else
    info "Pas encore de capture (elle sera créée au prochain démarrage de session)"
fi

# ------------------------------------------------------------
etape "6/8 - Le serveur Ollama est-il en ligne ?"
TAGS_JSON=""
if curl -s "$URL_TAGS" >/dev/null 2>&1; then
    TAGS_JSON=$(curl -s "$URL_TAGS" 2>/dev/null || true)
    ok "Serveur en ligne sur http://127.0.0.1:11434"
else
    info "Serveur pas en ligne pour l'instant"
fi

# ------------------------------------------------------------
etape "7/8 - Le serveur voit-il ton modèle nexus-axiom-ai ?"
MODELE_SERVI=0
if [[ -n "$TAGS_JSON" ]] && printf '%s' "$TAGS_JSON" | grep -q '"nexus-axiom-ai'; then
    MODELE_SERVI=1
    ok "Le serveur voit nexus-axiom-ai"
    printf '%s' "$TAGS_JSON" | python3 -c "import sys,json; [print('     -', m['name']) for m in json.load(sys.stdin).get('models',[])]" 2>/dev/null | tee -a "$RAPPORT"
else
    ko "Le serveur ne voit PAS nexus-axiom-ai"
    if [[ -n "$TAGS_JSON" ]]; then
        info "Pourtant il répond. Modèles qu'il voit :"
        printf '%s' "$TAGS_JSON" | python3 -c "import sys,json; [print('     -', m['name']) for m in json.load(sys.stdin).get('models',[])]" 2>/dev/null | tee -a "$RAPPORT"
        [[ -n "$MODELES" ]] && info "Diagnostic : le modèle est bien sur disque ($MODELES) mais le serveur est parti avec un AUTRE dossier -> problème d'environnement GNOME"
    fi
fi

# ------------------------------------------------------------
etape "8/8 - Lanceur GNOME"
if [[ -f "$DESKTOP" ]] && [[ -f "$WRAPPER" ]]; then
    ok "Lanceur GNOME présent : $DESKTOP"
    ANCIEN=$(grep -m1 '^export OLLAMA_MODELES=' "$WRAPPER" 2>/dev/null | sed 's/^export OLLAMA_MODELES=//' | tr -d '"')
    if [[ -n "$ANCIEN" && -n "$MODELES" && "$ANCIEN" != "$MODELES" ]]; then
        ko "Le lanceur actuel pointe vers : $ANCIEN  (le vrai dossier est : $MODELES) -> à réparer"
    elif [[ -n "$ANCIEN" ]]; then
        ok "Le lanceur pointe déjà vers le bon dossier : $ANCIEN"
    fi
else
    ko "Lanceur GNOME absent ou incomplet -> à (re)créer"
fi

# ============================================================
#  RÉPARATIONS
# ============================================================
REPARES=""
if [[ "$MODE_DIAG_SEUL" != "1" && -n "$MODELES" ]]; then

    etape "RÉPARATION 1/3 - Écriture du lanceur (chemin des modèles gravé EN DUR dedans)"
    {
        cat <<'W1'
#!/usr/bin/env bash
# NEXUS - serveur Ollama pour session GNOME (régénéré par nexus-gnome-docteur.sh)
# Le chemin des modèles est écrit EN DUR ici car GNOME ne lit PAS ~/.bashrc.
export PATH="/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$PATH"
W1
        printf 'export OLLAMA_MODELES="%s"\n' "$MODELES"
        if [[ "$FORCER_CPU" == "1" ]]; then
            cat <<'W2'

# --- pas de GPU -> tout en CPU, silencieux et suffisant pour un 3B ---
export CUDA_VISIBLE_DEVICES=""
export HIP_VISIBLE_DEVICES="-1"
export ROCR_VISIBLE_DEVICES="-1"
W2
        fi
        cat <<'W3'

# --- RAM économe : 1 seul modèle en mémoire, déchargé après 5 min d'inactivité ---
export OLLAMA_MAX_LOADED_MODELS=1
export OLLAMA_NUM_PARALLEL=1
export OLLAMA_KEEP_ALIVE=5m
export OLLAMA_HOST=127.0.0.1:11434

# --- capture de l'environnement exact vu par GNOME (pour ce docteur) ---
mkdir -p "$HOME/logs"
env | sort > "$HOME/logs/nexus-env-gnome.txt"

# déjà lancé ? on ne touche à rien
if curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    exit 0
fi

setsid nohup ollama serve >> "$HOME/logs/ollama.log" 2>&1 &

# on attend que le port réponde (max 60 s)
for i in $(seq 1 60); do
    curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && exit 0
    sleep 1
done
exit 1
W3
    } > "$WRAPPER"
    chmod +x "$WRAPPER"
    ok "Lanceur réécrit : $WRAPPER (OLLAMA_MODELES=$MODELES, CPU=$([[ $FORCER_CPU == 1 ]] && echo forcé || echo auto), RAM économe)"
    REPARES="${REPARES}lanceur, "

    etape "RÉPARATION 2/3 - Enregistrement dans GNOME (démarrage automatique)"
    cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=NEXUS - Serveur Ollama
Comment=Serveur Ollama pour nexus-axiom-ai (chemin des modèles et CPU forcé inclus)
Exec=$HOME/.local/bin/nexus-serve.sh
Terminal=false
X-GNOME-Autostart-enabled=true
Categories=Utility;
EOF
    ok "GNOME lancera le serveur tout seul à chaque session : $DESKTOP"
    REPARES="${REPARES}GNOME, "

    etape "RÉPARATION 3/3 - Redémarrage propre du serveur si nécessaire"
    if [[ "$MODELE_SERVI" != "1" ]]; then
        info "Le serveur ne voyait pas ton modèle -> on le redémarre avec le BON environnement"
        pkill -f "ollama serve" 2>/dev/null; sleep 2
        pkill -9 -f "ollama serve" 2>/dev/null; sleep 1
        "$WRAPPER" || true
        VU=0
        for i in $(seq 1 60); do
            TAGS_JSON=$(curl -s "$URL_TAGS" 2>/dev/null || true)
            if [[ -n "$TAGS_JSON" ]] && printf '%s' "$TAGS_JSON" | grep -q '"nexus-axiom-ai'; then
                VU=1; break
            fi
            sleep 1
        done
        if [[ "$VU" == "1" ]]; then
            ok "Serveur relancé et cette fois il voit ton modèle :"
            printf '%s' "$TAGS_JSON" | python3 -c "import sys,json; [print('     -', m['name']) for m in json.load(sys.stdin).get('models',[])]" 2>/dev/null | tee -a "$RAPPORT"
            REPARES="${REPARES}serveur, "
        else
            ko "Le serveur ne voit toujours pas le modèle -> regarde ~/logs/ollama.log"
        fi
    else
        ok "Pas besoin de redémarrer : le serveur voyait déjà ton modèle"
    fi

    # Preuve finale SANS charger le modèle en RAM ni toucher le GPU :
    # /api/show ne lit que le manifeste et le Modelfile (SYSTEM inclus).
    etape "PREUVE FINALE - La mémoire du modèle est bien là (0 GPU, 0 RAM chargée)"
    REP_SHOW=$(curl -s "$URL_SHOW" -d '{"model":"nexus-axiom-ai"}' 2>/dev/null || true)
    TAILLE_SYS=$(printf '%s' "$REP_SHOW" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    mf = d.get('modelfile','')
    print(len(mf) if 'SYSTEM' in mf else '')
except Exception:
    print('')" 2>/dev/null || true)
    if [[ -n "$TAILLE_SYS" && "$TAILLE_SYS" != "0" ]]; then
        ok "nexus-axiom-ai répond : son Modelfile (avec le SYSTEM, tes scripts condensés) fait $TAILLE_SYS caractères"
        ok "Vérifié sans jamais charger le modèle en RAM ni utiliser le GPU"
    else
        info "/api/show n'a pas répondu comme prévu (pas grave si le modèle est listé ci-dessus)"
    fi
fi

# ============================================================
#  VERDICT
# ============================================================
echo ""
echo "============================================================" | tee -a "$RAPPORT"
if [[ "$MODE_DIAG_SEUL" == "1" ]]; then
    echo "DIAGNOSTIC TERMINÉ (rien n'a été modifié) : $NB_OK OK, $NB_KO KO" | tee -a "$RAPPORT"
    echo "Pour réparer :  bash nexus-gnome-docteur.sh" | tee -a "$RAPPORT"
elif [[ -n "${REPARES%, }" ]]; then
    echo "RÉPARÉ : ${REPARES%, }" | tee -a "$RAPPORT"
    echo "Au prochain démarrage de l'ordi, GNOME lancera le serveur" | tee -a "$RAPPORT"
    echo "tout seul, avec le bon dossier, en CPU, en RAM économe." | tee -a "$RAPPORT"
    echo "" | tee -a "$RAPPORT"
    echo "Et maintenant, dans n'importe quel terminal :" | tee -a "$RAPPORT"
    echo "    ollama run nexus-axiom-ai" | tee -a "$RAPPORT"
else
    echo "Bilan : $NB_OK OK, $NB_KO KO" | tee -a "$RAPPORT"
    [[ -z "$MODELES" ]] && echo "Le modèle est introuvable sur le disque -> relance nexus-tout-en-un.sh" | tee -a "$RAPPORT"
fi
echo "Rapport détaillé : $RAPPORT" | tee -a "$RAPPORT"
echo "============================================================" | tee -a "$RAPPORT"
