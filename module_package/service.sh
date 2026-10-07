#!/system/bin/sh
MODDIR="${0%/*}"

# 1. Destravar imediatamente qualquer modo vitrine (300mA) no boot
echo 0 > /sys/class/power_supply/battery/batt_slate_mode 2>/dev/null
echo 0 > /sys/class/power_supply/battery/store_mode 2>/dev/null

# 2. Carregar configuracao do usuario (Padrao Seguro: NORMAL)
CONFIG="$MODDIR/config.prop"
if [ -f "$CONFIG" ]; then
    . "$CONFIG"
else
    PROFILE="NORMAL"
    COOLING_PRIORITY=0
    BYPASS_THERMAL=0
    SCREEN_ON_BYPASS=0
fi

# 3. Habilitar interruptores nativos de carregamento rapido OneUI
settings put system super_fast_charging 1 > /dev/null 2>&1
settings put system adaptive_fast_charging 1 > /dev/null 2>&1
settings put system fast_charging 1 > /dev/null 2>&1

# Desativar protect_battery APENAS se explicitamente configurado no perfil ULTRA
if [ "$PROFILE" = "ULTRA" ]; then
    settings put global protect_battery 0 > /dev/null 2>&1
    settings put system battery_protection 0 > /dev/null 2>&1
fi

# 4. Aguardar pd_policy_manager carregar no kernel (loop POSIX puro)
i=1
while [ $i -le 30 ]; do
    if lsmod | grep -q pd_policy_manager || grep -q "usbpd_pd_contact" /proc/kallsyms; then
        break
    fi
    sleep 1
    i=$((i + 1))
done

# 5. Carregar driver de kprobe (@cai0fps)
if ! lsmod | grep -qE "aw35615_whole|pps_kp_override"; then
    chmod 644 "$MODDIR/pps_kp_override.ko" 2>/dev/null
    insmod "$MODDIR/pps_kp_override.ko" > "$MODDIR/driver.log" 2>&1
fi

# Frequencias de CPU (Cluster Silver e Gold)
LITTLE_MAX="/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"
BIG_MAX="/sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq"

# Deteccao dinamica das frequencias maximas reais do processador
LITTLE_DEFAULT=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || echo 1900800)
BIG_DEFAULT=$(cat /sys/devices/system/cpu/cpu4/cpufreq/cpuinfo_max_freq 2>/dev/null || echo 2400000)

LITTLE_COOL=1190400
BIG_COOL=1056000

LITTLE_ULTRA_COOL=902400
BIG_ULTRA_COOL=825600

# Daemon em Segundo Plano
(
is_capped=0
pps_notified=0

while true; do
    # Recarregar configuracao do usuario dinamicamente (para mudancas em tempo real via WebUI)
    [ -f "$CONFIG" ] && . "$CONFIG"

    # Sempre manter o modo vitrine / 300mA desligado
    echo 0 > /sys/class/power_supply/battery/batt_slate_mode 2>/dev/null
    
    # Verificar se esta conectado ao carregador
    ac_val=$(cat /sys/class/power_supply/ac/online 2>/dev/null || echo 0)
    usb_val=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)
    st_val=$(cat /sys/class/power_supply/battery/status 2>/dev/null || echo "")
    if [ "$ac_val" = "1" ] || [ "$usb_val" = "1" ] || [ "$st_val" = "Charging" ] || [ "$st_val" = "Full" ]; then
        ac_online=1
    else
        ac_online=0
    fi
    
    # Deteccao confiavel de tela ligada via wakefulness
    if dumpsys power 2>/dev/null | grep -q "mWakefulness=Awake"; then
        screen_on=1
    else
        screen_on=0
    fi
    
    # ========================================================
    # MODO 3 (ULTRA): RELAXAMENTO TERMICO COM HISTÉRESE DE SEGURANÇA
    # ========================================================
    # Desarme de mitigador apenas sob temperatura comprovadamente fria (< 38 C).
    # Se atingir >= 40 C, cessa qualquer interferencia e permite que o daemon termico
    # atue livremente.
    if [ "$PROFILE" = "ULTRA" ] && [ "$BYPASS_THERMAL" = "1" ]; then
        if [ "$ac_online" = "1" ]; then
            b_temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 300)
            if [ "$b_temp" -lt 380 ]; then
                for cdev in /sys/class/thermal/cooling_device*; do
                    [ -d "$cdev" ] || continue
                    ctype=$(cat "$cdev/type" 2>/dev/null)
                    case "$ctype" in
                        *battery*|*charge*|*chg*)
                            cstate=$(cat "$cdev/cur_state" 2>/dev/null || echo 0)
                            [ "$cstate" != "0" ] && echo 0 > "$cdev/cur_state" 2>/dev/null
                            ;;
                    esac
                done
            fi
        fi
    fi
    
    # ========================================================
    # LOGICA DE ARREFECIMENTO DINAMICO DE CPU COM RESET DE ESTADO
    # ========================================================
    target_cap=0
    if [ "$ac_online" = "1" ] && [ "$screen_on" = "0" ]; then
        if [ "$PROFILE" = "ULTRA" ]; then
            target_cap=2
        elif [ "$COOLING_PRIORITY" = "1" ]; then
            target_cap=1
        fi
    fi

    if [ "$target_cap" != "$is_capped" ]; then
        if [ "$target_cap" = "2" ]; then
            chmod 644 "$LITTLE_MAX" "$BIG_MAX" 2>/dev/null
            echo $LITTLE_ULTRA_COOL > "$LITTLE_MAX" 2>/dev/null
            echo $BIG_ULTRA_COOL > "$BIG_MAX" 2>/dev/null
        elif [ "$target_cap" = "1" ]; then
            chmod 644 "$LITTLE_MAX" "$BIG_MAX" 2>/dev/null
            echo $LITTLE_COOL > "$LITTLE_MAX" 2>/dev/null
            echo $BIG_COOL > "$BIG_MAX" 2>/dev/null
        else
            chmod 644 "$LITTLE_MAX" "$BIG_MAX" 2>/dev/null
            echo $LITTLE_DEFAULT > "$LITTLE_MAX" 2>/dev/null
            echo $BIG_DEFAULT > "$BIG_MAX" 2>/dev/null
        fi
        is_capped=$target_cap
    fi

    # ========================================================
    # NOTIFICACAO NATIVA DO SISTEMA AO ENGATAR PPS
    # ========================================================
    is_pps_active=0
    # PPS so pode ser engatado se conectado em tomada AC (ac_val=1)
    if [ "$ac_val" = "1" ]; then
        dc_now=$(cat /sys/class/power_supply/battery/direct_charging_status 2>/dev/null || cat /sys/devices/platform/soc/soc:qcom,nopmi-chg/power_supply/battery/direct_charging_status 2>/dev/null || echo 0)
        cp_st=$(cat /sys/class/power_supply/charger_standalone/status 2>/dev/null || echo "")
        ib_ua=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo 0)

        # Corrente >= 1850mA entrando na celula (positivo) confirma modo SP2130 2:1
        if [ "$dc_now" != "0" ] || [ "$cp_st" = "Charging" ] || [ "$ib_ua" -ge 1850000 ]; then
            is_pps_active=1
        fi
    fi

    if [ "$is_pps_active" = "1" ]; then
        if [ "$pps_notified" = "0" ]; then
            sys_locale=$(getprop persist.sys.locale 2>/dev/null || echo "pt-BR")
            if echo "$sys_locale" | grep -qi "pt"; then
                n_title="⚡ Super Fast Charging (PPS)"
                n_msg="Protocolo PPS detectado! Charge Pump SP2130 (2:1) ativo."
            else
                n_title="⚡ Super Fast Charging (PPS)"
                n_msg="PPS Protocol detected! Silergy SP2130 (2:1) engaged."
            fi
            cmd notification post -S bigtext -t "$n_title" "pps_unlock_notif" "$n_msg" >/dev/null 2>&1
            pps_notified=1
        fi
    else
        # Ao desconectar da tomada AC, reseta o indicador para notificar na proxima conexao
        if [ "$ac_val" = "0" ]; then
            pps_notified=0
        fi
    fi
    
    sleep 2
done
) >/dev/null 2>&1 &
