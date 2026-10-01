#!/system/bin/sh
MODDIR="${0%/*}"

# 1. Destravar imediatamente qualquer modo vitrine (300mA) no boot
echo 0 > /sys/class/power_supply/battery/batt_slate_mode 2>/dev/null
echo 0 > /sys/class/power_supply/battery/store_mode 2>/dev/null

# 2. Desativar protecoes nativas de corte OneUI (80/85%)
settings put global protect_battery 0 > /dev/null 2>&1
settings put system battery_protection 0 > /dev/null 2>&1
settings put system super_fast_charging 1 > /dev/null 2>&1
settings put system adaptive_fast_charging 1 > /dev/null 2>&1
settings put system fast_charging 1 > /dev/null 2>&1

# 3. Aguardar pd_policy_manager carregar no kernel (loop POSIX puro)
i=1
while [ $i -le 30 ]; do
    if lsmod | grep -q pd_policy_manager || grep -q "usbpd_pd_contact" /proc/kallsyms; then
        break
    fi
    sleep 1
    i=$((i + 1))
done

# 4. Carregar driver de kprobe universal assinado (@cai0fps)
if ! lsmod | grep -qE "aw35615_whole|pps_kp_override"; then
    chmod 644 "$MODDIR/pps_kp_override.ko" 2>/dev/null
    insmod "$MODDIR/pps_kp_override.ko" > "$MODDIR/driver.log" 2>&1
fi

# 5. Carregar configuracao do usuario
CONFIG="$MODDIR/config.prop"
if [ -f "$CONFIG" ]; then
    . "$CONFIG"
else
    PROFILE="ULTRA"
    COOLING_PRIORITY=2
    BYPASS_THERMAL=1
    SCREEN_ON_BYPASS=1
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
    # MODO 3 (ULTRA): BYPASS TERMICO
    # ========================================================
    if [ "$PROFILE" = "ULTRA" ] || [ "$BYPASS_THERMAL" = "1" ]; then
        if [ "$ac_online" = "1" ]; then
            # Desarmar apenas se o thermal-engine tentar ativar mitigacao (>0)
            c26=$(cat /sys/class/thermal/cooling_device26/cur_state 2>/dev/null || echo 0)
            [ "$c26" != "0" ] && echo 0 > /sys/class/thermal/cooling_device26/cur_state 2>/dev/null
            c27=$(cat /sys/class/thermal/cooling_device27/cur_state 2>/dev/null || echo 0)
            [ "$c27" != "0" ] && echo 0 > /sys/class/thermal/cooling_device27/cur_state 2>/dev/null
        fi
    fi
    
    # ========================================================
    # LOGICA DE ARREFECIMENTO DINAMICO DE CPU
    # ========================================================
    if [ "$ac_online" = "1" ] && [ "$screen_on" = "0" ]; then
        if [ "$PROFILE" = "ULTRA" ]; then
            # Arrefecimento Ultra em standby
            if [ "$is_capped" = "0" ]; then
                chmod 644 "$LITTLE_MAX" "$BIG_MAX" 2>/dev/null
                echo $LITTLE_ULTRA_COOL > "$LITTLE_MAX" 2>/dev/null
                echo $BIG_ULTRA_COOL > "$BIG_MAX" 2>/dev/null
                is_capped=1
            fi
        elif [ "$COOLING_PRIORITY" = "1" ]; then
            # Arrefecimento Modo Inteligente em standby
            if [ "$is_capped" = "0" ]; then
                chmod 644 "$LITTLE_MAX" "$BIG_MAX" 2>/dev/null
                echo $LITTLE_COOL > "$LITTLE_MAX" 2>/dev/null
                echo $BIG_COOL > "$BIG_MAX" 2>/dev/null
                is_capped=1
            fi
        elif [ "$COOLING_PRIORITY" = "0" ] && [ "$is_capped" = "1" ]; then
            chmod 644 "$LITTLE_MAX" "$BIG_MAX" 2>/dev/null
            echo $LITTLE_DEFAULT > "$LITTLE_MAX" 2>/dev/null
            echo $BIG_DEFAULT > "$BIG_MAX" 2>/dev/null
            is_capped=0
        fi
    else
        # Tela ligada ou fora da tomada: restaurar frequencias normais de CPU
        if [ "$is_capped" = "1" ]; then
            chmod 644 "$LITTLE_MAX" "$BIG_MAX" 2>/dev/null
            echo $LITTLE_DEFAULT > "$LITTLE_MAX" 2>/dev/null
            echo $BIG_DEFAULT > "$BIG_MAX" 2>/dev/null
            is_capped=0
        fi
    fi
    
    sleep 2
done
) >/dev/null 2>&1 &
