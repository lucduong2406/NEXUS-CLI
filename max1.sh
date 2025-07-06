#!/bin/bash

# Script tự động tạo các tmux session và chạy lệnh nexus-network start với node ID riêng
# Sửa lỗi: Xử lý lỗi HTML từ curl, bảo vệ script gốc
# Tính năng:
# - Đọc node IDs từ tệp node_ids.txt
# - Tự động cài đặt tmux, bc, nexus-network
# - Kiểm tra tải CPU thông minh
# - Hỗ trợ tùy chỉnh qua biến môi trường
# - Log chi tiết vào logs/

# Cấu hình mặc định
: "${LOAD_THRESHOLD:=2.0}"  # Ngưỡng tải CPU
: "${TIMEOUT_SECONDS:=30}"  # Thời gian chờ tối đa
: "${TMUX_SESSION:=nexus-nodes}"  # Tên session tmux
: "${NODE_IDS_FILE:=node_ids.txt}"  # Tệp node IDs
: "${LOG_DIR:=logs}"  # Thư mục log
: "${VERBOSE_LOG:=1}"  # 1: log chi tiết, 0: ngắn gọn
: "${CHECK_LOAD:=1}"  # 1: kiểm tra tải CPU, 0: bỏ qua
NEXUS_URL="https://cli.nexus.xyz/"  # URL cài đặt nexus-network

# Khởi tạo log
mkdir -p "$LOG_DIR" || { echo "Lỗi: Không thể tạo thư mục $LOG_DIR"; exit 1; }
LOG_FILE="$LOG_DIR/nexus_network_start_$(date +%F_%H-%M-%S).log"
echo "Bắt đầu script tại $(date)" > "$LOG_FILE"

# Hàm ghi log
log() {
    local level=$1 message=$2
    if [ "$VERBOSE_LOG" -eq 1 ] || [ "$level" != "INFO" ]; then
        echo "$level: $message" | tee -a "$LOG_FILE"
    fi
}

# Hàm xử lý lỗi
handle_error() {
    local message=$1 exit_code=${2:-1}
    log "ERROR" "$message"
    exit "$exit_code"
}

# Hàm kiểm tra và cài đặt gói
install_package() {
    local package=$1 install_cmd=$2
    if ! command -v "$package" &> /dev/null; then
        log "INFO" "Đang cài đặt $package..."
        if ! sudo -n true 2>/dev/null; then
            handle_error "Cần quyền sudo để cài đặt $package. Chạy script với sudo hoặc cài đặt thủ công."
        fi
        if ! $install_cmd; then
            handle_error "Không thể cài đặt $package. Kiểm tra kết nối mạng hoặc cài đặt thủ công."
        fi
        log "INFO" "$package đã được cài đặt."
    fi
}

# Hàm kiểm tra node_id hợp lệ (phải là số nguyên)
validate_node_id() {
    local id=$1
    if [[ ! "$id" =~ ^[0-9]+$ ]]; then
        log "WARNING" "Node ID $id không hợp lệ (phải là số nguyên). Bỏ qua."
        return 1
    fi
    return 0
}

# Hàm kiểm tra phản hồi curl
check_curl_response() {
    local url=$1 output_file=$2
    # Kiểm tra mã HTTP
    local http_code=$(curl -s -o "$output_file" -w "%{http_code}" "$url")
    if [ "$http_code" -ne 200 ]; then
        handle_error "Lỗi curl: Nhận mã HTTP $http_code từ $url. Kiểm tra URL hoặc mạng."
    fi
    # Kiểm tra nội dung có phải HTML không
    if grep -qi "<!DOCTYPE html" "$output_file"; then
        handle_error "Lỗi curl: Phản hồi từ $url là HTML, không phải script. Kiểm tra URL hoặc server."
    fi
}

# Kiểm tra môi trường
install_package "tmux" "sudo apt update && sudo apt install -y tmux"
install_package "bc" "sudo apt update && sudo apt install -y bc"
if ! command -v nexus-network &> /dev/null; then
    log "INFO" "Đang cài đặt nexus-network CLI..."
    TEMP_SCRIPT="/tmp/nexus_install_$$.sh"
    # Tải và kiểm tra script cài đặt
    check_curl_response "$NEXUS_URL" "$TEMP_SCRIPT"
    # Đảm bảo tệp có quyền thực thi
    chmod +x "$TEMP_SCRIPT" || handle_error "Không thể cấp quyền thực thi cho $TEMP_SCRIPT."
    # Thực thi script cài đặt
    if ! sh "$TEMP_SCRIPT"; then
        rm -f "$TEMP_SCRIPT"
        handle_error "Không thể cài đặt nexus-network CLI. Kiểm tra kết nối mạng hoặc cài đặt thủ công bằng 'curl $NEXUS_URL | sh'."
    fi
    rm -f "$TEMP_SCRIPT"
    # Kiểm tra lại
    if ! command -v nexus-network &> /dev/null; then
        handle_error "nexus-network CLI vẫn không khả dụng sau khi cài đặt."
    fi
    log "INFO" "nexus-network CLI đã được cài đặt."
fi

# Kiểm tra quyền ghi vào /tmp
[ -w "/tmp" ] || handle_error "Không có quyền ghi vào /tmp. Kiểm tra quyền hoặc cấu hình TMUX_TMPDIR."

# Kiểm tra và tạo tệp node_ids.txt
if [ ! -f "$NODE_IDS_FILE" ]; then
    log "INFO" "Tệp $NODE_IDS_FILE không tồn tại. Tạo tệp mẫu..."
    cat << EOF > "$NODE_IDS_FILE"
# Danh sách node IDs, mỗi dòng chứa một ID (chỉ số nguyên)
# Ví dụ:
# 12485507
# 12485503
12485507
12485503
12485336
12485317
12484488
12456602
12456075
12456035
12455371
12427239
12426365
12401732
12401726
12401506
12401448
12401256
12401220
12400563
12387123
12387112
12322413
12322220
12321956
12321541
12259513
12259512
12259498
12259318
12259256
12259088
EOF
    log "INFO" "Đã tạo tệp mẫu $NODE_IDS_FILE. Vui lòng kiểm tra và chỉnh sửa nếu cần."
fi

# Đọc node_ids từ tệp
node_ids=()
while IFS= read -r line; do
    if [[ -n "$line" && ! "$line" =~ ^# ]]; then
        if validate_node_id "$line"; then
            node_ids+=("$line")
        fi
    fi
done < "$NODE_IDS_FILE"

# Kiểm tra danh sách node_ids
[ ${#node_ids[@]} -gt 0 ] || handle_error "Không tìm thấy node ID hợp lệ trong $NODE_IDS_FILE. Thêm ít nhất một ID."
log "INFO" "Đã đọc ${#node_ids[@]} node ID từ $NODE_IDS_FILE."

# Kiểm tra và đóng session tmux hiện có
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    log "INFO" "Session $TMUX_SESSION đã tồn tại. Đang đóng session cũ..."
    tmux kill-session -t "$TMUX_SESSION" || handle_error "Không thể đóng session $TMUX_SESSION. Chạy 'tmux kill-session -t $TMUX_SESSION' thủ công."
fi

# Tạo tmux session mới
tmux new-session -d -s "$TMUX_SESSION" || handle_error "Không thể tạo tmux session $TMUX_SESSION. Kiểm tra cấu hình tmux hoặc quyền hệ thống."

# Hàm chạy lệnh cho node
run_node() {
    local node_id=$1
    log "INFO" "Đang tạo window cho node-id $node_id..."
    if ! tmux new-window -t "$TMUX_SESSION" -n "Node-$node_id"; then
        log "ERROR" "Không thể tạo window cho node-id $node_id."
        return 1
    fi
    tmux send-keys -t "$TMUX_SESSION:Node-$node_id" "nexus-network start --node-id $node_id || echo 'Lỗi: node-id $node_id thất bại'" C-m
}

# Mở window và chạy lệnh cho mỗi node
start_time_epoch=$(date +%s)
for node_id in "${node_ids[@]}"; do
    run_node "$node_id"
    
    # Độ trễ thông minh (bỏ qua nếu CHECK_LOAD=0)
    if [ "$CHECK_LOAD" -eq 1 ] && [ -f /proc/loadavg ]; then
        while true; do
            load=$(awk '{print $1}' /proc/loadavg)
            if [ "$(echo "$load <= $LOAD_THRESHOLD" | bc)" -eq 1 ]; then
                break
            fi
            current_time_epoch=$(date +%s)
            if [ $((current_time_epoch - start_time_epoch)) -ge $TIMEOUT_SECONDS ]; then
                log "WARNING" "Timeout sau $TIMEOUT_SECONDS giây, tải hệ thống vẫn cao ($load). Tiếp tục..."
                break
            fi
            log "INFO" "Hệ thống đang tải cao ($load), chờ 5 giây..."
            sleep 5
        done
    else
        [ "$CHECK_LOAD" -eq 1 ] && log "WARNING" "Không tìm thấy /proc/loadavg, bỏ qua kiểm tra tải hệ thống."
        sleep 1  # Độ trễ tối thiểu
    fi
done

# Kết thúc
log "INFO" "Hoàn tất: Đã tạo ${#node_ids[@]} window trong tmux session '$TMUX_SESSION'."
log "INFO" "Để xem các window, chạy: tmux attach -t $TMUX_SESSION"
log "INFO" "Để chỉnh sửa node IDs, mở tệp $NODE_IDS_FILE và thêm/xóa ID (mỗi ID trên một dòng)."
log "INFO" "Chi tiết log tại $LOG_FILE"
