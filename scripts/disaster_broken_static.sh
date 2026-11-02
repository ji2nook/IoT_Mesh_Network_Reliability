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

# --- 현재 라즈베리파이 정보 자동 설정 ---
MY_IP=${NODE_IPS[$PI_NUM]}

# --- 실험 결과 저장 폴더 및 로그 파일 경로 설정 ---
RESULTS_DIR="/home/raspberrypi${PI_NUM}/results"
mkdir -p "$RESULTS_DIR"
LOG_FILE="${RESULTS_DIR}/Static_Broken_result_pi${PI_NUM}_$(date +%Y%m%d_%H%M%S).txt"


# --- 스크립트 시작 ---
echo "--- [$(date)] Pi ${PI_NUM} (정적 라우팅 - 노드 파손) 스크립트 시작 ---" | tee -a "$LOG_FILE"


# --- 네트워크 인터페이스 설정 ---
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

# --- IP 주소 할당 및 커널 파라미터 설정 ---
sudo ifconfig wlan0 "${MY_IP}/24" up
echo "IP 주소 할당 완료: ${MY_IP}" | tee -a "$LOG_FILE"

sudo sysctl -w net.ipv4.ip_forward=1
echo "IP 포워딩 활성화 완료." | tee -a "$LOG_FILE"

# ICMP Redirect 기능 비활성화 (노드 역할에 따라 다르게 설정)
case $PI_NUM in
    1|5) # Endpoint 노드 (Pi 1, 5)
        # Redirect 메시지를 받지 않도록 설정
        sudo sysctl -w net.ipv4.conf.all.accept_redirects=0
        sudo sysctl -w net.ipv4.conf.wlan0.accept_redirects=0
        echo "ICMP Redirect 수신 기능을 비활성화합니다." | tee -a "$LOG_FILE"
        ;;
    2|3|4) # Router 노드 (Pi 2, 3, 4)
        # Redirect 메시지를 보내지 않도록 설정
        sudo sysctl -w net.ipv4.conf.all.send_redirects=0
        sudo sysctl -w net.ipv4.conf.wlan0.send_redirects=0
        echo "ICMP Redirect 전송 기능을 비활성화합니다." | tee -a "$LOG_FILE"
        ;;
esac
# 이웃 노드 탐색 시간 대기
echo "이웃 노드 탐색을 위해 15초간 대기..." | tee -a "$LOG_FILE"
sleep 15

# --- 정적 라우팅 테이블 설정 ---
echo "정적 라우팅 테이블을 설정합니다..." | tee -a "$LOG_FILE"
sudo ip route flush table main

case $PI_NUM in
    1) # 그룹 A의 끝. 이웃: 2
        (sudo ip route add 10.0.0.2/32 dev wlan0 || true)
        (sudo ip route add default via 10.0.0.2 || true)
        ;;
    2) # 그룹 A의 라우터. 이웃: 1, 3
        (sudo ip route add 10.0.0.1/32 dev wlan0 || true)
        (sudo ip route add 10.0.0.3/32 dev wlan0 || true)
        (sudo ip route add 10.0.0.4/32 via 10.0.0.3 || true)
        (sudo ip route add 10.0.0.5/32 via 10.0.0.3 || true)
        ;;
    3) # 브릿지 노드. 이웃: 2, 4
        (sudo ip route add 10.0.0.2/32 dev wlan0 || true)
        (sudo ip route add 10.0.0.4/32 dev wlan0 || true)
        (sudo ip route add 10.0.0.1/32 via 10.0.0.2 || true)
        (sudo ip route add 10.0.0.5/32 via 10.0.0.4 || true)
        ;;
    4) # 그룹 B의 라우터. 이웃: 3, 5
        (sudo ip route add 10.0.0.5/32 dev wlan0 || true)
        (sudo ip route add 10.0.0.3/32 dev wlan0 || true)
        (sudo ip route add 10.0.0.2/32 via 10.0.0.3 || true)
        (sudo ip route add 10.0.0.1/32 via 10.0.0.3 || true)
        ;;
    5) # 그룹 B의 끝. 이웃: 4
        (sudo ip route add 10.0.0.4/32 dev wlan0 || true)
        (sudo ip route add default via 10.0.0.4 || true)
        ;;
esac

echo "라우팅 테이블:" | tee -a "$LOG_FILE"
ip route | tee -a "$LOG_FILE"

echo "네트워크 안정화를 위해 60초간 추가 대기..." | tee -a "$LOG_FILE"
sleep 60


# --- 실험 시나리오 분기 ---

if [ "$PI_NUM" -eq 1 ]; then
    # ==========================================================================
    # --- 시나리오: Pi 1 (테스트 로그 작성) ---
    # ==========================================================================
    echo "=== [정상 상태] 모든 노드 성능 측정 (각 5회) ===" | tee -a "$LOG_FILE"
    ping -c 5 10.0.0.2 >> "$LOG_FILE" || true
    ping -c 5 10.0.0.3 >> "$LOG_FILE" || true
    ping -c 5 10.0.0.4 >> "$LOG_FILE" || true
    ping -c 5 10.0.0.5 >> "$LOG_FILE" || true

    echo "" | tee -a "$LOG_FILE"
    echo "--- [$(date)] PI3(10.0.0.3) 노드 파손 감지를 시작합니다... ---" | tee -a "$LOG_FILE"
    echo "이제 3번 노드의 전원을 차단해 주십시오." | tee -a "$LOG_FILE"
    while ping -c 1 -W 2 10.0.0.3 > /dev/null 2>&1; do
        sleep 2
    done
    echo "!!! [$(date)] PI3 노드 파손 감지됨 !!!" | tee -a "$LOG_FILE"

    echo "" | tee -a "$LOG_FILE"
    echo "=== [PI3 파손 후] 다른 노드 연결성 확인 (각 5회) ===" | tee -a "$LOG_FILE"
    ping -c 5 10.0.0.2 >> "$LOG_FILE" || true
    ping -c 5 10.0.0.3 >> "$LOG_FILE" || true
    ping -c 5 10.0.0.4 >> "$LOG_FILE" || true
    ping -c 5 10.0.0.5 >> "$LOG_FILE" || true

elif [ "$PI_NUM" -eq 3 ]; then
    # ==========================================================================
    # --- 시나리오: Pi 3 (장애 발생 (파손) 노드) ---
    # ==========================================================================
    echo "Pi 3 (장애 발생 (파손) 노드)입니다. 약 1분 30초 후 자동 종료를 시뮬레이션합니다." | tee -a "$LOG_FILE"
    sleep 90 
    echo "!!! [$(date)] 장애 발생 시뮬레이션: 시스템을 종료합니다. !!!" | tee -a "$LOG_FILE"
    sudo reboot

else
    # ==========================================================================
    # --- 시나리오: Pi 2, 4, 5 (중계 노드) ---
    # ==========================================================================
    echo "Pi ${PI_NUM}입니다. 대기 모드로 전환합니다. (약 5분 후 자동 재부팅)" | tee -a "$LOG_FILE"
    sleep 300
fi

# --- 5. 실험 종료 ---
echo "" | tee -a "$LOG_FILE"
echo "--- [$(date)] 실험 종료. 10초 후 재부팅합니다. ---" | tee -a "$LOG_FILE"
sleep 10
sudo reboot
