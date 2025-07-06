#!/bin/bash

# Script tự động tạo các tmux session và chạy lệnh nexus-network start với node ID riêng
# Cải tiến: Tự động cài đặt tmux và nexus-network nếu chưa có

# Cấu hình
LOAD_THRESHOLD=2.0  # Ngưỡng tải CPU
TIMEOUT_SECONDS=30  # Thời gian chờ tối đa khi tải cao
TMUX_SESSION="nexus-nodes"  # Tên session tmux
LOG_FILE="nexus_network_start_$(date +%F_%H-%M-%S).log"

# Danh sách node IDs
node_ids=(
    12485507 12485503 12485336 12485317 12484488
    12456602 12456075 12456035 12455371 12427239
    12426365 12401732 12401726 12401506 12401448
    12401256 12401220 12400563 12387123 12387112
    12322413 12322220 12321956 12321541 12259513
    12259512 12259498 12259318 12259256 12259088
)

# Ghi log
echo "Bắt đầu script tại $(date)" > "$LOG_FILE"
echo "Phiên bản tmux: $(tmux -V 2>/dev/null || echo 'tmux chưa cài đặt')" >> "$LOG_FILE"

# Hàm kiểm tra và cài đặt gói
install_package() {
    local package=$1
    local install_cmd=$2
    if ! command -v "$package" &> /dev/null; then
        echo "Đang cài đặt $package..." | tee -a "$LOG_FILE"
        if ! sudo -n true 2>/dev/null; then
            echo "Lỗi: Cần quyền sudo để cài đặt $package. Vui lòng chạy script với quyền sudo hoặc cài đặt thủ công." | tee -a "$LOG_FILE"
            exit 1
        fi
        if ! $install_cmd; then
            echo "Lỗi: Không thể cài đặt $package. Vui lòng kiểm tra kết nối mạng hoặc cài đặt thủ công." | tee -a "$LOG_FILE"
            exit 1
        fi
        echo "$package đã được cài đặt." | tee -a "$LOG_FILE"
    fi
}

# Kiểm tra và cài đặt tmux
install_package "tmux" "sudo apt update && sudo apt install -y tmux"

# Kiểm tra và cài đặt bc (dùng để so sánh tải CPU)
install_package "bc" "sudo apt update && sudo apt install -y bc"

# Kiểm tra và cài đặt nexus-network
if ! command -v nexus-network &> /dev/null; then
    echo "Đang cài đặt nexus-network CLI..." | tee -a "$LOG_FILE"
    if ! curl https://cli.nexus.xyz/ | sh; then
        echo "Lỗi: Không thể cài đặt nexus-network CLI. Vui lòng kiểm tra kết nối mạng hoặc cài đặt thủ công bằng 'curl https://cli.nexus.xyz/ | sh'." | tee -a "$LOG_FILE"
        exit 1
    fi
    # Kiểm tra lại sau khi cài đặt
    if ! command -v nexus-network &> /dev/null; then
        echo "Lỗi: nexus-network CLI vẫn không khả dụng sau khi cài đặt." | tee -a "$LOG_FILE"
        exit 1
    fi
    echo "nexus-network CLI đã được cài đặt." | tee -a "$LOG_FILE"
fi

# Kiểm tra quyền ghi vào thư mục tạm của tmux
if [ ! -w "/tmp" ]; then
    echo "Lỗi: Không có quyền ghi vào /tmp. Vui lòng kiểm tra quyền hoặc cấu hình TMUX_TMPDIR." | tee -a "$LOG_FILE"
    exit 1
fi

# Kiểm tra và đóng session tmux hiện có
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "Cảnh báo: Session $TMUX_SESSION đã tồn tại. Đang đóng session cũ..." | tee -a "$LOG_FILE"
    tmux kill-session -t "$TMUX_SESSION" || {
        echo "Lỗi: Không thể đóng session $TMUX_SESSION. Vui lòng kiểm tra quyền hoặc chạy 'tmux kill-session -t $TMUX_SESSION' thủ công." | tee -a "$LOG_FILE"
        exit 1
    }
fi

# Tạo tmux session mới
tmux new-session -d -s "$TMUX_SESSION" || {
    echo "Lỗi: Không thể tạo tmux session $TMUX_SESSION. Vui lòng kiểm tra cấu hình tmux hoặc quyền hệ thống." | tee -a "$LOG_FILE"
    echo "Thử chạy 'tmux -V' để kiểm tra phiên bản tmux và 'tmux list-sessions' để xem các session hiện có." | tee -a "$LOG_FILE"
    exit 1
}

# Mở window và chạy lệnh cho mỗi node
for node_id in "${node_ids[@]}"; do
    echo "Đang tạo window cho node-id $node_id..." | tee -a "$LOG_FILE"
    
    # Tạo window mới trong tmux session
    tmux new-window -t "$TMUX_SESSION" -n "Node-$node_id" || {
        echo "Lỗi: Không thể tạo window cho node-id $node_id." | tee -a "$LOG_FILE"
        continue
    }
    
    # Gửi lệnh vào window
    tmux send-keys -t "$TMUX_SESSION:Node-$node_id" "nexus-network start --node-id $node_id || echo 'Lỗi: node-id $node_id thất bại'" C-m
    
    # Độ trễ thông minh: chờ đến khi CPU usage giảm hoặc timeout
    if [ -f /proc/loadavg ]; then
        start_time=$(date +%s)
        while true; do
            load=$(awk '{print $1}' /proc/loadavg)
            if [ "$(echo "$load <= $LOAD_THRESHOLD" | bc)" -eq 1 ]; then
                break
            fi
            current_time=$(date +%s)
            if [ $((current_time - start_time)) -ge $TIMEOUT_SECONDS ]; then
                echo "Cảnh báo: Timeout sau $TIMEOUT_SECONDS giây, tải hệ thống vẫn cao ($load). Tiếp tục..." | tee -a "$LOG_FILE"
                break
            fi
            echo "Hệ thống đang tải cao ($load), chờ 5 giây..." | tee -a "$LOG_FILE"
            sleep 5
        done
    else
        echo "Cảnh báo: Không tìm thấy /proc/loadavg, bỏ qua kiểm tra tải hệ thống." | tee -a "$LOG_FILE"
        sleep 5  # Độ trễ mặc định nếu không đọc được loadavg
    fi
done

echo "Hoàn tất: Đã tạo ${#node_ids[@]} window trong tmux session '$TMUX_SESSION'." | tee -a "$LOG_FILE"
echo "Để xem các window, chạy: tmux attach -t $TMUX_SESSION" | tee -a "$LOG_FILE"
echo "Chi tiết log tại $LOG_FILE" | tee -a "$LOG_FILE"
