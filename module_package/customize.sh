SKIPUNZIP=0

ui_print "=================================================="
ui_print "   GALAXY A05s — SUPER FAST CHARGE (PPS UNLOCK)   "
ui_print "            Versao v3.5 Universal                 "
ui_print "               por @cai0fps                       "
ui_print "=================================================="
ui_print ""
ui_print " [!] AVISO LEGAL E CONSENTIMENTO DE USO:"
ui_print "  Projeto experimental para testes e pesquisa."
ui_print "  O autor (@cai0fps) NAO se responsabiliza e NAO"
ui_print "  arca com quaisquer problemas, danos materiais,"
ui_print "  desgaste da bateria ou perda de garantia."
ui_print "  O uso deste modulo como um todo e em qualquer"
ui_print "  modo e de sua exclusiva e inteira responsabilidade!"
ui_print "=================================================="
ui_print ""

# Limpar modulos antigos remanescentes para evitar conflitos
rm -rf "/data/adb/modules/pps_fase3a" 2>/dev/null
rm -rf "/data/adb/modules/pps_fase2" 2>/dev/null
rm -f "/data/adb/modules/disable" 2>/dev/null

# Desbloquear imediatamente qualquer trava residual
echo 0 > /sys/class/power_supply/battery/batt_slate_mode 2>/dev/null
echo 0 > /sys/class/power_supply/battery/store_mode 2>/dev/null

ui_print "[*] Controles do Instalador:"
ui_print "    [VOL -] = Navegar / Mudar Opcao"
ui_print "    [VOL +] = CONFIRMAR Opcao Selecionada"
ui_print ""

# Seletor interativo com cursor
choose_profile() {
    local selected=3
    local total=3
    
    print_menu() {
        ui_print "--------------------------------------------------"
        ui_print " Selecione o Perfil de Carregamento:"
        ui_print " [VOL -] = Mudar Opcao | [VOL +] = CONFIRMAR"
        ui_print "--------------------------------------------------"
        if [ "$selected" = "1" ]; then
            ui_print " [>] 1. Modo Normal (PPS 25W Padrao ate 100%)"
        else
            ui_print " [ ] 1. Modo Normal (PPS 25W Padrao ate 100%)"
        fi
        if [ "$selected" = "2" ]; then
            ui_print " [>] 2. Modo Inteligente (Arrefecimento de CPU em tela apagada)"
        else
            ui_print " [ ] 2. Modo Inteligente (Arrefecimento de CPU em tela apagada)"
        fi
        if [ "$selected" = "3" ]; then
            ui_print " [>] 3. Modo ULTRA (25W Maximo Forcado + Bypass Termico)"
        else
            ui_print " [ ] 3. Modo ULTRA (25W Maximo Forcado + Bypass Termico)"
        fi
        ui_print " -> Aperte [VOL-] para alternar ou [VOL+] para confirmar..."
    }
    
    print_menu
    local start_time=$(date +%s 2>/dev/null || echo 0)
    
    while true; do
        local line
        line=$(timeout 1 getevent -lqc 1 2>/dev/null)
        case "$line" in
            *KEY_VOLUMEDOWN*DOWN*|*0072*00000001*)
                # Espera soltar a tecla VOL-
                while true; do
                    local rel=$(timeout 1 getevent -lqc 1 2>/dev/null)
                    case "$rel" in
                        *KEY_VOLUMEDOWN*UP*|*0072*00000000*|"") break ;;
                    esac
                done
                sleep 0.15
                
                # Incrementa cursor
                if [ "$selected" -ge "$total" ]; then
                    selected=1
                else
                    selected=$((selected + 1))
                fi
                ui_print ""
                print_menu
                start_time=$(date +%s 2>/dev/null || echo 0)
                ;;
                
            *KEY_VOLUMEUP*DOWN*|*0073*00000001*)
                # Espera soltar a tecla VOL+
                while true; do
                    local rel=$(timeout 1 getevent -lqc 1 2>/dev/null)
                    case "$rel" in
                        *KEY_VOLUMEUP*UP*|*0073*00000000*|"") break ;;
                    esac
                done
                sleep 0.2
                
                ui_print ""
                ui_print "[+] CONFIRMADO: Opcao $selected selecionada!"
                return $selected
                ;;
        esac
        
        # Timeout de inatividade de 30s (padrao: Modo 3 ULTRA)
        local now=$(date +%s 2>/dev/null || echo 0)
        if [ "$now" -gt 0 ] && [ "$((now - start_time))" -ge 30 ]; then
            ui_print ""
            ui_print "[i] Timeout (30s sem clique). Confirmando Opcao $selected automaticamente."
            return $selected
        fi
    done
}

choose_profile
CHOICE=$?

SEL_PROFILE="ULTRA"
SEL_COOLING="2"
SEL_BYPASS_THERMAL="1"
SEL_SCREEN_BYPASS="1"

case "$CHOICE" in
    1)
        SEL_PROFILE="NORMAL"
        SEL_COOLING="0"
        SEL_BYPASS_THERMAL="0"
        SEL_SCREEN_BYPASS="0"
        ui_print "[>] Perfil Selecionado: Modo 1 (Normal 25W / 100%)"
        ;;
    2)
        SEL_PROFILE="SMART"
        SEL_COOLING="1"
        SEL_BYPASS_THERMAL="0"
        SEL_SCREEN_BYPASS="0"
        ui_print "[>] Perfil Selecionado: Modo 2 (Inteligente 25W Turbo / 100%)"
        ;;
    3|*)
        SEL_PROFILE="ULTRA"
        SEL_COOLING="2"
        SEL_BYPASS_THERMAL="1"
        SEL_SCREEN_BYPASS="1"
        ui_print "[>] Perfil Selecionado: Modo 3 (ULTRA Potencia Maxima / 25W Forcado + Bypass Termico)"
        ui_print " [!] AVISO: Modo ULTRA com Bypass Termico e de Tela ativado."
        ;;
esac

ui_print ""
ui_print " [!] TERMO: O usuario declara pleno consentimento e assume 100% da"
ui_print "     responsabilidade por quaisquer problemas ou danos causados pelo uso."
ui_print ""
ui_print "[*] Gravando configuracao do usuario..."
cat <<EOF > "$MODPATH/config.prop"
# Configuracao do Modulo Super Fast Charge A05s por @cai0fps
PROFILE=$SEL_PROFILE
MAX_PERCENT=100
COOLING_PRIORITY=$SEL_COOLING
BYPASS_THERMAL=$SEL_BYPASS_THERMAL
SCREEN_ON_BYPASS=$SEL_SCREEN_BYPASS
FORCE_SFC=1
EOF

ui_print "[+] Perfil Gravado   : $SEL_PROFILE"
ui_print "[+] Carga Maxima     : 100% (Sem travas de corte)"
ui_print "[+] Arrefecimento    : Nivel $SEL_COOLING"
ui_print "[+] Bypass Termico   : $SEL_BYPASS_THERMAL (Desarma throttling Qualcomm)"
ui_print "[+] Bypass de Tela   : $SEL_SCREEN_BYPASS (Potencia maxima com tela ligada)"
ui_print ""

# Permissoes de execucao
chmod 755 "$MODPATH/service.sh"
chmod 755 "$MODPATH/action.sh" 2>/dev/null
chmod 644 "$MODPATH/pps_kp_override.ko" 2>/dev/null

ui_print "[+] Instalacao concluida com sucesso!"
ui_print "[+] Reinicie o dispositivo para ativar o Super Fast Charging 25W."
