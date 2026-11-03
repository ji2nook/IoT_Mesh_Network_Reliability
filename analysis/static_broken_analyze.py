import os
import re
import numpy as np


def analyze_all_experiments(base_path: str) -> tuple:
    """
    정적 라우팅 전파 방해 실험 폴더 5개를 순회하며 개별 및 전체 통계를 분석한다.
    각 실험 폴더(ex1 ~ ex5)에서 Static_Broken_result_pi*.txt 파일을 읽어
    정상 상태와 전파 방해 이후의 패킷 손실률, RTT, 경로 복구 시간을 산출한다.
    """
    experiment_folders = [f"ex{i}" for i in range(1, 6)]
    
    # 전체 실험 결과 취합
    total_results = {
        "normal_loss": [], "normal_rtt": [],
        "broken_loss": [], "broken_rtt": [],
        "recovery_time": []
    }
    
    # 개별 실험 결과 저장
    per_experiment_stats = []
    
    analyzed_file_count = 0
    
    print("전파 방해 실험 데이터 분석을 시작합니다...")
    
    # 정규 표현식 패턴
    normal_section_regex = re.compile(r"===\s*\[정상 상태\].*?===(.*?)===", re.DOTALL)
    broken_section_regex = re.compile(r"===\s*\[복구 후\].*?===(.*?)===", re.DOTALL)
    loss_regex = re.compile(r"([\d.]+)\s*%\s*packet loss")
    rtt_regex = re.compile(r"rtt min/avg/max/mdev\s*=\s*.*?/([\d.]+)/")
    recovery_regex = re.compile(r"우회 경로 활성화 소요 시간:\s*([\d.]+)초")
    
    for folder_name in experiment_folders:
        folder_path = os.path.join(base_path, folder_name)
        if not os.path.isdir(folder_path):
            continue
        
        print(f"  - '{folder_name}' 폴더 분석 중...")
        
        # 개별 실험 데이터를 임시 저장
        current_exp_data = {key: [] for key in total_results}
        combined_content = ""
        
        for filename in os.listdir(folder_path):
            if "Static_Broken_result_pi" in filename and filename.endswith(".txt") and "pi3" not in filename:
                file_path = os.path.join(folder_path, filename)
                try:
                    with open(file_path, "r", encoding="utf-8-sig") as f:
                        combined_content += f.read() + "\n===\n"
                        analyzed_file_count += 1
                except Exception as e:
                    print(f"    오류: '{filename}' 파일을 읽는 중 문제 발생: {e}")
        
        # 정보 추출
        for section in normal_section_regex.findall(combined_content):
            matches = loss_regex.findall(section)
            if matches:
                current_exp_data["normal_loss"].append(float(matches[-1]))
            matches = rtt_regex.findall(section)
            if matches:
                current_exp_data["normal_rtt"].append(float(matches[-1]))
        
        for section in broken_section_regex.findall(combined_content):
            matches = loss_regex.findall(section)
            if matches:
                current_exp_data["broken_loss"].append(float(matches[-1]))
            matches = rtt_regex.findall(section)
            if matches:
                current_exp_data["broken_rtt"].append(float(matches[-1]))
        
        for time in recovery_regex.findall(combined_content):
            current_exp_data["recovery_time"].append(float(time))
        
        # 개별 실험 통계 계산 및 저장
        exp_summary = {"name": folder_name}
        for key, values in current_exp_data.items():
            # 전체 통계를 위해 데이터 추가
            total_results[key].extend(values)
            # 개별 실험의 평균 계산
            exp_summary[key] = np.mean(values) if values else "N/A"
        per_experiment_stats.append(exp_summary)
    
    #전체 통계 계산
    final_stats = {
        key: {"mean": np.mean(values), "std": np.std(values)} if values else {"mean": "N/A", "std": "N/A"}
        for key, values in total_results.items()
    }
    return final_stats, analyzed_file_count, per_experiment_stats


def format_stat(value: float | str, unit: str) -> str:
    if isinstance(value, (int, float)):
        return f"{value:.3f}{unit}"
    return value

def log(text: str, f) -> None:
    print(text)
    f.write(text + "\n")

# 파일 생성 실행
if __name__ == "__main__":
    current_directory = "./raw_results/Broken/Static_Routing/"
    output_path = "./results/static_broken_summary.txt"
    with open(output_path, "w", encoding="utf-8") as f:
        final_stats, file_count, per_experiment_stats = analyze_all_experiments(current_directory)
        
        log("\n--- 각 실험별 분석 결과 ---", f)
        for stats in per_experiment_stats:
            log(f"\n[{stats['name']}]", f)
            log(f"  - 정상 상태: 손실률={format_stat(stats['normal_loss'], "%")}, RTT={format_stat(stats['normal_rtt'], ' ms')}", f)
            log(f"  - 전파 방해 상태: 손실률={format_stat(stats['broken_loss'], "%")}, RTT={format_stat(stats['broken_rtt'], ' ms')}", f)
            log(f"  - 경로 복구 시간: {format_stat(stats['recovery_time'], ' 초')}", f)
        
        log("\n\n--- 최종 실험 결과 분석 (1차 ~ 5차 종합) ---", f)
        if file_count > 0:
            log(f"분석한 파일 개수: {file_count}개", f)
            log("\n[정상 상태]", f)
            log(f"  - 평균 패킷 손실률: {format_stat(final_stats['normal_loss']['mean'], '%')} (표준편차: {format_stat(final_stats['normal_loss']['std'], '')})", f)
            log(f"  - 평균 지연 시간(RTT): {format_stat(final_stats['normal_rtt']['mean'], 'ms')} (표준편차: {format_stat(final_stats['normal_rtt']['std'], '')})", f)
            log("\n[전파 방해 상태]", f)
            log(f"  - 평균 패킷 손실률: {format_stat(final_stats['broken_loss']['mean'], '%')} (표준편차: {format_stat(final_stats['broken_loss']['std'], '')})", f)
            log(f"  - 평균 지연 시간(RTT): {format_stat(final_stats['broken_rtt']['mean'], 'ms')} (표준편차: {format_stat(final_stats['broken_rtt']['std'], '')})", f)
            log(f"  - 평균 경로 복구 시간: {format_stat(final_stats['recovery_time']['mean'], '초')} (표준편차: {format_stat(final_stats['recovery_time']['std'], '')})", f)
        else:
            log("분석할 파일을 찾지 못했습니다.", f)