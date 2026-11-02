#!/bin/bash
set -e

# ==============================================================================
#                      기본 설정 (각 라즈베리파이 번호 입력)
# ==============================================================================
PI_NUM=1
# ==============================================================================

# --- 각 라즈베리파이 IP 및 MAC 주소 정보 ---
declare -A NODE_IPS
NODE_IPS[1]="10.0.0.1"
NODE_IPS[2]="10.0.0.2"
NODE_IPS[3]="10.0.0.3"
NODE_IPS[4]="10.0.0.4"
NODE_IPS[5]="10.0.0.5"

declare -A NODE_MACS
NODE_MACS[1]="d8:3a:dd:47:7c:13"
NODE_MACS[2]="d8:3a:dd:47:7b:8c"
NODE_MACS[3]="d8:3a:dd:38:6d:1d"
NODE_MACS[4]="d8:3a:dd:43:d8:17"
NODE_MACS[5]="d8:3a:dd:47:6f:06"

# --- 현재 파이의 정보 자동 설정 ---
MY_IP=${NODE_IPS[$PI_NUM]}
MY_MAC=${NODE_MACS[$PI_NUM]}

# --- 실험 결과 저장 폴더 및 로그 파일 경로 설정 ---
RESULTS_DIR="/home/raspberrypi${PI_NUM}/results"
mkdir -p "$RESULTS_DIR"
LOG_FILE="${RESULTS_DIR}/Mesh_Broken_result_pi${PI_NUM}_$(date +%Y%m%d_%H%M%S).txt"


# --- 스크립트 시작 ---
echo "--- [$(date)] Pi ${PI_NUM} (메시 네트워크 - 노드 파손) 스크립트 시작 ---" | tee -a "$LOG_FILE"


# --- 1. 네트워크 및 B.A.T.M.A.N. 설정 ---
echo "--- 네트워크 설정 시작 ---" | tee -a "$LOG_FILE"
sudo systemctl stop NetworkManager || true
sudo killall wpa_supplicant || true
sudo ip link set wlan0 down
sudo iw dev wlan0 set type ibss
sudo ip link set wlan0 up

echo "${PI_NUM}번 노드, 네트워크 참여 전 $(( ($PI_NUM - 1) * 3 ))초 대기..." | tee -a "$LOG_FILE"
sleep $(( ($PI_NUM - 1) * 3 ))
if ! sudo iw dev wlan0 ibss join disaster_mesh 2412; then
    echo "!!!!!! [실패] 네트워크 참여(ibss join) 중 오류 발생 !!!!!!" | tee -a "$LOG_FILE"
    exit 1
fi
echo "[성공] Ad-Hoc 네트워크 참여 완료." | tee -a "$LOG_FILE"



# --- B.A.T.M.A.N. 활성화 (먼저 실행) ---
# iptables에서 bat0를 사용해야 하므로, 인터페이스를 먼저 생성합니다.
echo "--- B.A.T.M.A.N. 활성화 ---" | tee -a "$LOG_FILE"
sudo modprobe batman-adv
sudo batctl if add wlan0
sudo ifconfig bat0 "${MY_IP}/24" up
echo "B.A.T.M.A.N. 활성화 완료." | tee -a "$LOG_FILE"


# --- 소프트웨어 차폐 (나중에 실행) ---
echo "--- [소프트웨어 차폐] IP 패킷 전달 경로를 iptables로 설정합니다... ---" | tee -a "$LOG_FILE"

# iptables 설치 및 초기화
sudo apt-get update > /dev/null && sudo apt-get install -y iptables > /dev/null
sudo iptables -F FORWARD
sudo iptables -P FORWARD DROP

# IP 포워딩 활성화
sudo sysctl -w net.ipv4.ip_forward=1

# 선형 토폴로지를 위한 패킷 전달 규칙 설정
case $PI_NUM in
    2)
        sudo iptables -A FORWARD -i bat0 -o bat0 -s ${NODE_IPS[1]} -d ${NODE_IPS[3]} -j ACCEPT
        sudo iptables -A FORWARD -i bat0 -o bat0 -s ${NODE_IPS[3]} -d ${NODE_IPS[1]} -j ACCEPT
        ;;
    3)
        sudo iptables -A FORWARD -i bat0 -o bat0 -s ${NODE_IPS[2]} -d ${NODE_IPS[4]} -j ACCEPT
        sudo iptables -A FORWARD -i bat0 -o bat0 -s ${NODE_IPS[4]} -d ${NODE_IPS[2]} -j ACCEPT
        ;;
    4)
        sudo iptables -A FORWARD -i bat0 -o bat0 -s ${NODE_IPS[3]} -d ${NODE_IPS[5]} -j ACCEPT
        sudo iptables -A FORWARD -i bat0 -o bat0 -s ${NODE_IPS[5]} -d ${NODE_IPS[3]} -j ACCEPT
        ;;
esac
echo "--- [소프트웨어 차폐] 설정 완료 ---" | tee -a "$LOG_FILE"

echo "네트워크 안정화를 위해 60초간 대기..." | tee -a "$LOG_FILE"
sleep 60




# --- 실험 시나리오 분기 ---

if [ "$PI_NUM" -eq 1 ]; then
    # ==========================================================================
    # === 시나리오: Pi 1 (테스트 측정 노드) ===
    # ==========================================================================
    echo "=== [정상 상태] PI5(10.0.0.5) 경로 및 성능 측정 ===" | tee -a "$LOG_FILE"
    #echo "예상 경로: 1 -> 2 -> 3 -> 4 -> 5" | tee -a "$LOG_FILE"
    (sudo batctl tr ${NODE_MACS[5]} || true) >> "$LOG_FILE"
    ping -c 10 -i 0.5 ${NODE_IPS[5]} >> "$LOG_FILE" || true

    echo "" | tee -a "$LOG_FILE"
    echo "--- [$(date)] 브릿지 노드 PI3(10.0.0.3) 파손 감지를 시작합니다... ---" | tee -a "$LOG_FILE"

    while ping -c 1 -W 2 10.0.0.3 > /dev/null 2>&1; do
        sleep 2
    done
    echo "!!! [$(date)] PI3 노드 파손 감지됨 !!!" | tee -a "$LOG_FILE"
    
    start_time=$(date +%s.%N)
    echo "대체 경로 탐색을 시작합니다. PI5(10.0.0.5) 연결을 확인합니다..." | tee -a "$LOG_FILE"
    
    # 복구될 때까지 0.1초 간격으로 ping 시도
    until ping -c 1 -W 0.1 10.0.0.5 > /dev/null 2>&1; do
        sleep 0.1
    done
    
    end_time=$(date +%s.%N)
    recovery_time=$(echo "$end_time - $start_time" | bc -l)
    printf "### [복구 완료] 우회 경로 활성화 소요 시간: %.4f초 ###\n" "$recovery_time" | tee -a "$LOG_FILE"

    echo "" | tee -a "$LOG_FILE"
    echo "=== [복구 후] PI5(10.0.0.5) 새로운 경로 및 성능 측정 ===" | tee -a "$LOG_FILE"
    #echo "예상 경로: 1 -> 2 -> 4 -> 5" | tee -a "$LOG_FILE"
    (sudo batctl tr ${NODE_MACS[5]} || true) >> "$LOG_FILE"
    ping -c 10 -i 0.5 ${NODE_IPS[5]} >> "$LOG_FILE" || true

elif [ "$PI_NUM" -eq 3 ]; then
    # ==========================================================================
    # === 시나리오: Pi 3 (장애 발생 (파손) 노드) ===
    # ==========================================================================
    echo "Pi 3 (장애 발생 (파손) 노드)입니다. 약 1분 30초 후 자동 종료를 시뮬레이션합니다." | tee -a "$LOG_FILE"
    # Pi 1이 정상 상태 측정을 마칠 충분한 시간을 줍니다.
    sleep 90 
    echo "!!! [$(date)] 장애 발생 시뮬레이션: 시스템을 종료합니다. !!!" | tee -a "$LOG_FILE"

else
    # ==========================================================================
    # === 시나리오: Pi 2, 4, 5 (중계 노드) ===
    # ==========================================================================
    echo "Pi ${PI_NUM} (중계 노드)입니다. 대기 모드로 전환합니다. (약 5분 후 자동 재부팅)" | tee -a "$LOG_FILE"
    sleep 300
fi


# --- 실험 종료 ---
echo "" | tee -a "$LOG_FILE"
echo "--- [$(date)] 실험 종료. 10초 후 재부팅합니다. ---" | tee -a "$LOG_FILE"
sleep 10
sudo reboot
