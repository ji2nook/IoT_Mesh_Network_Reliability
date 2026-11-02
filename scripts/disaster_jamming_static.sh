#!/bin/bash
set -e

# ==============================================================================
#                      기본 설정 (각 라즈베리파이 번호 입력)
# ==============================================================================
PI_NUM=1
# ==============================================================================

# --- 각 노드의 IP 주소 정보 ---
declare -A NODE_IPS
NODE_IPS[1]="10.0.0.1"
NODE_IPS[2]="10.0.0.2"
NODE_IPS[3]="10.0.0.3"
NODE_IPS[4]="10.0.0.4"
NODE_IPS[5]="10.0.0.5"

# --- 현재 파이의 정보 자동 설정 ---
MY_IP=${NODE_IPS[$PI_NUM]}

# --- 실험 결과 저장 폴더 및 로그 파일 경로 설정 ---
RESULTS_DIR="/home/raspberrypi${PI_NUM}/results"
mkdir -p "$RESULTS_DIR"
LOG_FILE="${RESULTS_DIR}/Static_Jamming_result_pi${PI_NUM}_$(date +%Y%m%d_%H%M%S).txt"


# --- 스크립트 시작 ---
echo "--- [$(date)] Pi ${PI_NUM} (정적 라우팅 - 전파 방해) 스크립트 시작 ---" | tee -a "$LOG_FILE"


# --- 1. 네트워크 인터페이스 설정 ---
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

# --- 2. IP 주소 할당 및 커널 파라미터 설정 ---
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
    # === 시나리오: Pi 1 (테스트 측정 노드) ===
    # ==========================================================================
    echo "=== [정상 상태] 모든 노드 성능 측정 (각 5회) ===" | tee -a "$LOG_FILE"
    ping -c 5 -i 0.5 10.0.0.2 >> "$LOG_FILE" || true
    ping -c 5 -i 0.5 10.0.0.3 >> "$LOG_FILE" || true
    ping -c 5 -i 0.5 10.0.0.4 >> "$LOG_FILE" || true
    ping -c 5 -i 0.5 10.0.0.5 >> "$LOG_FILE" || true

    echo "" | tee -a "$LOG_FILE"
    echo "--- [$(date)] PI3(10.0.0.3)의 전파 방해 상황을 감시합니다... ---" | tee -a "$LOG_FILE"
    
    # 3번 노드와의 통신이 끊어질 때까지 대기
    while ping -c 1 -W 2 10.0.0.3 > /dev/null 2>&1; do
        sleep 2
    done
    echo "!!! [$(date)] PI3 노드와 통신 두절 감지 (전파 방해로 추정) !!!" | tee -a "$LOG_FILE"

    # ... (PI3 노드 통신 두절 감지 후) ...
    echo "" | tee -a "$LOG_FILE"
    echo "=== [PI3 전파 방해 후] 모든 노드 연결성 동시 확인 (총 5회 반복) ===" | tee -a "$LOG_FILE"

    # 2, 3, 4, 5번 노드를 순회하며 ping 테스트하는 과정을 5번 반복
    for i in $(seq 1 5); do
        echo "--- [측정 ${i}회차] ---" | tee -a "$LOG_FILE"
    
        # 모든 대상 노드에 대해 한 번씩 ping 실행
        for target_pi in 2 3 4 5; do
            target_ip=${NODE_IPS[$target_pi]}
            ping -c 5 -W 1 ${target_ip} >> "$LOG_FILE" || true
            sleep 0.2 # 각 노드 ping 사이의 짧은 간격
        done
    
        echo "" >> "$LOG_FILE" # 라운드별 구분을 위해 빈 줄 추가
        sleep 1 # 다음 라운드 시작 전 1초 대기
    done

elif [ "$PI_NUM" -eq 3 ]; then
    # ==========================================================================
    # --- 시나리오: Pi 3 (장애 발생 (전파 방해) 노드) ---
    # ==========================================================================
    echo "Pi 3 (전파 방해 발생 노드)입니다. wlan0 인터페이스의 패킷 손실률을 점차 증가시킵니다." | tee -a "$LOG_FILE"
    
    # `tc`를 사용하기 위해 iproute2 패키지 설치
    sudo apt-get update > /dev/null && sudo apt-get install -y iproute2 > /dev/null
    # 기존 tc 규칙이 있다면 삭제 (초기화)
    sudo tc qdisc del dev wlan0 root 2>/dev/null || true

    echo "--- [$(date)] 전파 방해 시뮬레이션 시작 ---" | tee -a "$LOG_FILE"
    # 10초 간격으로 패킷 손실률을 10%씩 100%까지 증가시킴
    for loss in $(seq 10 10 100); do
        sleep 10
        echo "--- [$(date)] wlan0 인터페이스 패킷 손실률 ${loss}% 적용 ---" | tee -a "$LOG_FILE"
        sudo tc qdisc replace dev wlan0 root netem loss "${loss}%"
    done

    echo "!!! [$(date)] 전파 방해 시뮬레이션 완료 (손실률 100%). !!!" | tee -a "$LOG_FILE"

else
    # ==========================================================================
    # --- 시나리오: Pi 2, 4, 5 (중계 노드) ---
    # ==========================================================================
    echo "Pi ${PI_NUM}입니다. 대기 모드로 전환합니다. (약 5분 후 자동 재부팅)" | tee -a "$LOG_FILE"
    sleep 300
fi

# --- 실험 종료 ---
echo "" | tee -a "$LOG_FILE"
echo "--- [$(date)] 실험 종료. 10초 후 재부팅합니다. ---" | tee -a "$LOG_FILE"
sleep 10
sudo reboot
