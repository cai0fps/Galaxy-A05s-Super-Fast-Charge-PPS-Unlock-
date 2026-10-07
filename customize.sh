SKIPUNZIP=0

# Deteccao automatica de idioma (PT ou EN)
LOCALE=$(getprop persist.sys.locale 2>/dev/null || getprop ro.product.locale 2>/dev/null || echo "en")
case "$LOCALE" in
    pt*|PT*) IS_PT=1 ;;
    *) IS_PT=0 ;;
esac

if [ "$IS_PT" = "1" ]; then
    ui_print "=================================================="
    ui_print "   GALAXY A05s — SUPER FAST CHARGE (PPS UNLOCK)   "
    ui_print "            Versao v1.6 Universal                 "
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
else
    ui_print "=================================================="
    ui_print "   GALAXY A05s — SUPER FAST CHARGE (PPS UNLOCK)   "
    ui_print "            Version v1.6 Universal                "
    ui_print "                by @cai0fps                       "
    ui_print "=================================================="
    ui_print ""
    ui_print " [!] LEGAL DISCLAIMER & TERMS OF USE:"
    ui_print "  Experimental project for testing and research."
    ui_print "  The author (@cai0fps) is NOT responsible and does"
    ui_print "  NOT bear any liability for material damages, battery"
    ui_print "  wear, warranty voiding, or any issues caused."
    ui_print "  Use of this module as a whole and in any mode is"
    ui_print "  at the user's sole and exclusive responsibility!"
    ui_print "=================================================="
    ui_print ""
fi

# Limpar modulos antigos remanescentes para evitar conflitos
rm -rf "/data/adb/modules/pps_fase3a" 2>/dev/null
rm -rf "/data/adb/modules/pps_fase2" 2>/dev/null

# Desbloquear imediatamente qualquer trava residual
echo 0 > /sys/class/power_supply/battery/batt_slate_mode 2>/dev/null
echo 0 > /sys/class/power_supply/battery/store_mode 2>/dev/null

if [ "$IS_PT" = "1" ]; then
    ui_print "[*] Controles do Instalador:"
    ui_print "    [VOL -] = Navegar / Mudar Opcao"
    ui_print "    [VOL +] = CONFIRMAR Opcao Selecionada"
else
    ui_print "[*] Installer Controls:"
    ui_print "    [VOL -] = Navigate / Change Option"
    ui_print "    [VOL +] = CONFIRM Selected Option"
fi
ui_print ""

# Seletor interativo com cursor
choose_profile() {
    local selected=1
    local total=3
    
    print_menu() {
        ui_print "--------------------------------------------------"
        if [ "$IS_PT" = "1" ]; then
            ui_print " Selecione o Perfil de Carregamento:"
            ui_print " [VOL -] = Mudar Opcao | [VOL +] = CONFIRMAR"
        else
            ui_print " Select Charging Profile:"
            ui_print " [VOL -] = Change Option | [VOL +] = CONFIRM"
        fi
        ui_print "--------------------------------------------------"
        if [ "$selected" = "1" ]; then
            [ "$IS_PT" = "1" ] && ui_print " [>] 1. Modo Normal (Padrao Seguro - Curva Termica e CV Mantidas)" || ui_print " [>] 1. Normal Mode (Safe Default - Thermal & CV Curves Kept)"
        else
            [ "$IS_PT" = "1" ] && ui_print " [ ] 1. Modo Normal (Padrao Seguro - Curva Termica e CV Mantidas)" || ui_print " [ ] 1. Normal Mode (Safe Default - Thermal & CV Curves Kept)"
        fi
        if [ "$selected" = "2" ]; then
            [ "$IS_PT" = "1" ] && ui_print " [>] 2. Modo Inteligente (Arrefecimento de CPU em Standby)" || ui_print " [>] 2. Smart Mode (CPU Standby Cooldown with Safe Protections)"
        else
            [ "$IS_PT" = "1" ] && ui_print " [ ] 2. Modo Inteligente (Arrefecimento de CPU em Standby)" || ui_print " [ ] 2. Smart Mode (CPU Standby Cooldown with Safe Protections)"
        fi
        if [ "$selected" = "3" ]; then
            [ "$IS_PT" = "1" ] && ui_print " [>] 3. Modo ULTRA (Experimental - Mitigacao Termica Relaxada)" || ui_print " [>] 3. ULTRA Mode (Experimental - Relaxed Thermal Mitigation)"
        else
            [ "$IS_PT" = "1" ] && ui_print " [ ] 3. Modo ULTRA (Experimental - Mitigacao Termica Relaxada)" || ui_print " [ ] 3. ULTRA Mode (Experimental - Relaxed Thermal Mitigation)"
        fi
        [ "$IS_PT" = "1" ] && ui_print " -> Aperte [VOL-] para alternar ou [VOL+] para confirmar..." || ui_print " -> Press [VOL-] to cycle or [VOL+] to confirm..."
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
                if [ "$IS_PT" = "1" ]; then
                    ui_print "[+] CONFIRMADO: Opcao $selected selecionada!"
                else
                    ui_print "[+] CONFIRMED: Option $selected selected!"
                fi
                return $selected
                ;;
        esac
        
        # Timeout de inatividade de 30s (padrao: Modo 1 Normal - Seguro)
        local now=$(date +%s 2>/dev/null || echo 0)
        if [ "$now" -gt 0 ] && [ "$((now - start_time))" -ge 30 ]; then
            ui_print ""
            if [ "$IS_PT" = "1" ]; then
                ui_print "[i] Timeout (30s sem clique). Confirmando Opcao $selected (Modo Seguro) automaticamente."
            else
                ui_print "[i] Timeout (30s inactive). Auto-confirming Option $selected (Safe Mode)."
            fi
            return $selected
        fi
    done
}

choose_profile
CHOICE=$?

SEL_PROFILE="NORMAL"
SEL_COOLING="0"
SEL_BYPASS_THERMAL="0"
SEL_SCREEN_BYPASS="0"

case "$CHOICE" in
    1)
        SEL_PROFILE="NORMAL"
        SEL_COOLING="0"
        SEL_BYPASS_THERMAL="0"
        SEL_SCREEN_BYPASS="0"
        [ "$IS_PT" = "1" ] && ui_print "[>] Perfil Selecionado: Modo 1 (Normal Seguro - Protecoes Preservadas)" || ui_print "[>] Selected Profile: Mode 1 (Safe Normal - Protections Preserved)"
        ;;
    2)
        SEL_PROFILE="SMART"
        SEL_COOLING="1"
        SEL_BYPASS_THERMAL="0"
        SEL_SCREEN_BYPASS="0"
        [ "$IS_PT" = "1" ] && ui_print "[>] Perfil Selecionado: Modo 2 (Inteligente - Resfriamento CPU Standby)" || ui_print "[>] Selected Profile: Mode 2 (Smart - CPU Standby Cooldown)"
        ;;
    3)
        SEL_PROFILE="ULTRA"
        SEL_COOLING="2"
        SEL_BYPASS_THERMAL="1"
        SEL_SCREEN_BYPASS="1"
        if [ "$IS_PT" = "1" ]; then
            ui_print "[>] Perfil Selecionado: Modo 3 (ULTRA - Mitigacao Termica Relaxada)"
            ui_print " [!] AVISO: Modo ULTRA com relaxamento de limitadores termicos. Monitore a temperatura!"
        else
            ui_print "[>] Selected Profile: Mode 3 (ULTRA - Relaxed Thermal Mitigation)"
            ui_print " [!] NOTICE: ULTRA Mode with relaxed thermal throttlers. Monitor device temperatures!"
        fi
        ;;
    *)
        SEL_PROFILE="NORMAL"
        SEL_COOLING="0"
        SEL_BYPASS_THERMAL="0"
        SEL_SCREEN_BYPASS="0"
        [ "$IS_PT" = "1" ] && ui_print "[>] Perfil Selecionado: Modo 1 (Normal Seguro)" || ui_print "[>] Selected Profile: Mode 1 (Safe Normal)"
        ;;
esac

ui_print ""
if [ "$IS_PT" = "1" ]; then
    ui_print " [!] TERMO: O usuario declara pleno consentimento e assume 100% da"
    ui_print "     responsabilidade por quaisquer problemas ou danos causados pelo uso."
    ui_print ""
    ui_print "[*] Gravando configuracao do usuario..."
else
    ui_print " [!] TERMS: The user declares full consent and assumes 100% of the"
    ui_print "     responsibility for any issues or damages caused by the use."
    ui_print ""
    ui_print "[*] Saving user configuration..."
fi

cat <<EOF > "$MODPATH/config.prop"
# Configuracao do Modulo Super Fast Charge A05s por @cai0fps
PROFILE=$SEL_PROFILE
MAX_PERCENT=100
COOLING_PRIORITY=$SEL_COOLING
BYPASS_THERMAL=$SEL_BYPASS_THERMAL
SCREEN_ON_BYPASS=$SEL_SCREEN_BYPASS
FORCE_SFC=1
EOF

if [ "$IS_PT" = "1" ]; then
    ui_print "[+] Perfil Gravado   : $SEL_PROFILE"
    ui_print "[+] Carga Maxima     : 100% (Sem travas de corte)"
    ui_print "[+] Arrefecimento    : Nivel $SEL_COOLING"
    ui_print "[+] Bypass Termico   : $SEL_BYPASS_THERMAL (Desarma throttling Qualcomm)"
    ui_print "[+] Bypass de Tela   : $SEL_SCREEN_BYPASS (Potencia maxima com tela ligada)"
    ui_print ""
    ui_print "[+] Instalacao concluida com sucesso!"
    ui_print "[+] Reinicie o dispositivo para ativar o Super Fast Charging 25W."
else
    ui_print "[+] Saved Profile    : $SEL_PROFILE"
    ui_print "[+] Max Charge Limit : 100% (No cutoff clamps)"
    ui_print "[+] Cooling Priority : Level $SEL_COOLING"
    ui_print "[+] Thermal Bypass   : $SEL_BYPASS_THERMAL (Disarms Qualcomm throttling)"
    ui_print "[+] Screen-On Bypass : $SEL_SCREEN_BYPASS (Max power with screen on)"
    ui_print ""
    ui_print "[+] Installation completed successfully!"
    ui_print "[+] Reboot device to activate 25W Super Fast Charging."
fi

# Permissoes de execucao
chmod 755 "$MODPATH/service.sh"
chmod 755 "$MODPATH/action.sh" 2>/dev/null
chmod 755 "$MODPATH/diag.sh" 2>/dev/null
chmod 644 "$MODPATH/pps_kp_override.ko" 2>/dev/null
