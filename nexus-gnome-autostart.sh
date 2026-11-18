#!/usr/bin/env bash
# ============================================================
#  NEXUS GNOME AUTOSTART
#  Démarre le serveur Ollama AUTOMATIQUEMENT avec GNOME.
#  Plus besoin de taper "ollama serve" dans le terminal :
#  tu allumes l'ordi, tu ouvres un terminal, et tu parles
#  directement à ton modèle.
#
#  Usage :
#     bash nexus-gnome-autostart.sh            -> installe + démarre maintenant
#     bash nexus-gnome-autostart.sh --stop     -> arrête le serveur maintenant
#     bash nexus-gnome-autostart.sh --enlever  -> retire le démarrage auto
# ============================================================
set -u

ROUGE='\033[0;31m'; VERT='\033[0;32m'; JAUNE='\033[1;33m'; BLEU='\033[0;34m'; NORMAL='\033[0m'
etape() { echo -e "\n${BLEU}==> $1${NORMAL}"; }
ok()    { echo -e "${VERT}[OK]${NORMAL} $1"; }
err()   { echo -e "${ROUGE}[ERREUR]${NORMAL} $1"; }

# --- option --enlever : retirer le démarrage automatique
if [[ "${1:-}" == "--enlever" ]]; then
    rm -f "$HOME/.config/autostart/ollama-nexus.desktop"
    echo "Démarrage automatique retiré (GNOME ne lancera plus le serveur)."
    echo "Le modèle nexus-axiom-ai reste installé, rien ne se perd."
    exit 0
fi

# --- option --stop : arrêter le serveur maintenant
if [[ "${1:-}" == "--stop" ]]; then
    if pkill -f "ollama serve" 2>/dev/null; then
        echo "Serveur Ollama arrêté."
    else
        echo "Le serveur n'était pas lancé."
    fi
    exit 0
fi

# ================== INSTALLATION ==================
etape "Vérification d'Ollama"
export PATH="$PATH:/usr/local/bin:/usr/bin:$HOME/.local/bin"
if ! command -v ollama >/dev/null 2>&1; then
    err "Ollama n'est pas installé sur cette machine."
    err "Lance d'abord :  bash nexus-tout-en-un.sh"
    exit 1
fi
ok "Ollama trouvé : $(command -v ollama)"

etape "Création des dossiers"
mkdir -p "$HOME/.config/autostart" "$HOME/.local/bin" "$HOME/logs"
ok "prêts : ~/.config/autostart  ~/.local/bin  ~/logs"

etape "Installation du lanceur (tourne en arrière-plan, sans fenêtre)"
cat > "$HOME/.local/bin/nexus-serve.sh" <<'EOF'
#!/usr/bin/env bash
# NEXUS : démarre le serveur Ollama en arrière-plan (appelé par GNOME au démarrage)
export PATH="$PATH:/usr/local/bin:/usr/bin:$HOME/.local/bin"
mkdir -p "$HOME/logs"

# si le serveur tourne déjà -> rien à faire
if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
    exit 0
fi

# sinon on le lance (journal dans ~/logs/ollama.log)
setsid nohup ollama serve >> "$HOME/logs/ollama.log" 2>&1 &

# on attend que le port 11434 réponde (max 60 secondes)
for i in $(seq 1 60); do
    curl -s http://localhost:11434/api/tags >/dev/null 2>&1 && exit 0
    sleep 1
done
exit 1
EOF
chmod +x "$HOME/.local/bin/nexus-serve.sh"
ok "lanceur installé : ~/.local/bin/nexus-serve.sh"

etape "Enregistrement dans GNOME (démarrage automatique)"
cat > "$HOME/.config/autostart/ollama-nexus.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=NEXUS - Serveur Ollama
Comment=Démarre le serveur Ollama pour le modèle nexus-axiom-ai
Exec=PLACEHOLDER/.local/bin/nexus-serve.sh
Terminal=false
X-GNOME-Autostart-enabled=true
Categories=Utility;
EOF
sed -i "s|PLACEHOLDER|$HOME|g" "$HOME/.config/autostart/ollama-nexus.desktop"
ok "GNOME lancera le serveur tout seul à chaque ouverture de session"

etape "Test immédiat (le serveur démarre tout de suite)"
"$HOME/.local/bin/nexus-serve.sh"
if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
    ok "serveur Ollama en ligne sur http://localhost:11434"
    echo ""
    echo "Modèles disponibles :"
    curl -s http://localhost:11434/api/tags \
      | python3 -c "import sys,json; [print('  -', m['name']) for m in json.load(sys.stdin).get('models',[])]" 2>/dev/null || true
else
    err "le serveur n'a pas répondu — regarde le journal : ~/logs/ollama.log"
    exit 1
fi

echo ""
echo "============================================================"
echo "  C'EST FINI. À partir de maintenant :"
echo ""
echo "  1. Tu allumes ton ordi -> GNOME démarre le serveur"
echo "     tout seul (en arrière-plan, sans fenêtre)."
echo ""
echo "  2. Tu ouvres un terminal et tu tapes juste :"
echo "         ollama run nexus-axiom-ai"
echo ""
echo "  3. Arrêter le serveur maintenant :"
echo "         bash nexus-gnome-autostart.sh --stop"
echo ""
echo "  4. Retirer le démarrage automatique :"
echo "         bash nexus-gnome-autostart.sh --enlever"
echo "============================================================"
