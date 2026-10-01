SKIPUNZIP=0

ui_print "=================================================="
ui_print "   GALAXY A05s — SUPER FAST CHARGE (PPS UNLOCK)   "
ui_print "            Versao v3.3 Universal                 "
ui_print "               por @cai0fps                      "
ui_print "=================================================="
ui_print ""

# Limpar modulos antigos remanescentes para evitar conflitos
if [ -d "/data/adb/modules/pps_fase3a" ]; then
    ui_print "[*] Removendo versao de teste anterior (pps_fase3a)..."
    rm -rf "/data/adb/modules/pps_fase3a" 2>/dev/null
fi
if [ -d "/data/adb/modules/pps_fase2" ]; then
    ui_print "[*] Removendo versao de teste anterior (pps_fase2)..."
    rm -rf "/data/adb/modules/pps_fase2" 2>/dev/null
fi

# Desbloquear imediatamente qualquer trava de 300mA residual
echo 0 > /sys/class/power_supply/battery/batt_slate_mode 2>/dev/null
echo 0 > /sys/class/power_supply/battery/store_mode 2>/dev/null

# Helper robusto para deteccao de teclas de volume (anti-bounce e timeout 15s)
chooseport() {
    # Retorna 0 em VOL+, 1 em VOL-
    local key=""
    local start_time=$(date +%s 2>/dev/null || echo 0)
    
    # 1. Aguarda o evento de pressionar (DOWN) com timeout de 15s
    while true; do
        local line
        line=$(timeout 1 getevent -lqc 1 2>/dev/null)
        case "$line" in
            *KEY_VOLUMEUP*DOWN*|*0073*00000001*)
                key="UP"
                break
                ;;
            *KEY_VOLUMEDOWN*DOWN*|*0072*00000001*)
                key="DOWN"
                break
                ;;
        esac
        
        local now=$(date +%s 2>/dev/null || echo 0)
        if [ "$now" -gt 0 ] && [ "$((now - start_time))" -ge 15 ]; then
            ui_print "[i] Timeout (15s sem clique). Selecionando: Modo 2 (Inteligente 100%)."
            return 1
        fi
    done
    
    # 2. Aguarda o usuario soltar a tecla fisicamente (UP)
    while true; do
        local rel
        rel=$(timeout 1 getevent -lqc 1 2>/dev/null)
        case "$rel" in
            *KEY_VOLUMEUP*UP*|*0073*00000000*)
                [ "$key" = "UP" ] && break
                ;;
            *KEY_VOLUMEDOWN*UP*|*0072*00000000*)
                [ "$key" = "DOWN" ] && break
                ;;
            "")
                # Ja soltou a tecla
                break
                ;;
        esac
    done
    
    sleep 0.3
    
    if [ "$key" = "UP" ]; then
        return 0
    else
        return 1
    fi
}

ui_print "[*] Selecione o Perfil de Carregamento:"
ui_print "    [VOL+] = Modo 1: Normal (PPS Padrao 25W direto ate 100%)"
ui_print "    [VOL-] = Modo 2: Inteligente (PPS 25W + Arrefecimento de CPU ate 100%)"
ui_print ""

SEL_PROFILE="SMART"
SEL_COOLING="1"

if chooseport; then
    SEL_PROFILE="NORMAL"
    SEL_COOLING="0"
    ui_print "[>] Selecionado: Modo 1 (Normal 25W / 100%)"
else
    SEL_PROFILE="SMART"
    SEL_COOLING="1"
    ui_print "[>] Selecionado: Modo 2 (Inteligente 25W Turbo / 100%)"
fi

ui_print ""
ui_print "[*] Gravando configuracao..."
cat <<EOF > "$MODPATH/config.prop"
# Configuracao do Modulo Super Fast Charge A05s por @cai0fps
PROFILE=$SEL_PROFILE
MAX_PERCENT=100
COOLING_PRIORITY=$SEL_COOLING
FORCE_SFC=1
EOF

ui_print "[+] Perfil Gravado: $SEL_PROFILE"
ui_print "[+] Carga Maxima  : 100% (Sem travas de corte)"
ui_print "[+] Arrefecimento : $SEL_COOLING"
ui_print ""

# Permissoes de execucao
chmod 755 "$MODPATH/service.sh"
chmod 755 "$MODPATH/action.sh" 2>/dev/null
chmod 644 "$MODPATH/pps_kp_override.ko" 2>/dev/null

ui_print "[+] Instalacao concluida com sucesso!"
ui_print "[+] Reinicie o dispositivo para ativar o Super Fast Charging 25W."
