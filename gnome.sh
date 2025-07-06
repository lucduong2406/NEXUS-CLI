#!/bin/bash

# Script tự động mở các tab gnome-terminal và chạy lệnh nexus-network start với node ID riêng

# Kiểm tra môi trường
if ! command -v gnome-terminal &> /dev/null; then
    echo "Lỗi: gnome-terminal không được cài đặt. Vui lòng cài đặt bằng 'sudo apt install gnome-terminal'."
    exit 1
fi

if ! command -v nexus-network &> /dev/null; then
    echo "Lỗi: nexus-network CLI không được cài đặt. Cài đặt bằng 'curl https://cli.nexus.xyz/ | sh'."
    exit 1
fi

# Danh sách node IDs
node_ids=(
    12485507 12485503 12485336 12485317 12484488
    12456602 12456075 12456035 12455371 12427239
    12426365 12401732 12401726 12401506 12401448
    12401256 12401220 12400563 12387123 12387112
    12322413 12322220 12321956 12321541 12259513
    12259512 12259498 12259318 12259256 12259088
)

# Tệp log
LOG_FILE="nexus_network_start_$(date +%F_%H-%M-%S).log"
echo "Bắt đầu script tại $(date)" > "$LOG_FILE"

# Hàm kiểm tra trạng thái tab
check_tab_status() {
    local node_id=$1
    local pid=$2
    sleep 5  # Chờ tab khởi động
    if ! ps -p "$pid" > /dev/null; then
        echo "Lỗi: Tab cho node-id $node_id không khởi động thành công" | tee -a "$LOG_FILE"
        return 1
    fi
    return 0
}

# Mở tab và chạy lệnh
for node_id in "${node_ids[@]}"; do
    echo "Đang mở tab cho node-id $node_id..." | tee -a "$LOG_FILE"
    
    # Mở tab mới với lệnh
    gnome-terminal --tab --title="Node $node_id" -- bash -c "nexus-network start --node-id $node_id || echo \"Lỗi: node-id $node_id thất bại\"; exec bash" &
    
    # Lưu PID của lệnh gnome-terminal
    tab_pid=$!
    
    # Kiểm tra trạng thái tab
    if ! check_tab_status "$node_id" "$tab_pid"; then
        echo "Tiếp tục với node-id tiếp theo..." | tee -a "$LOG_FILE"
        continue
    fi
    
    # Độ trễ thông minh: chờ đến khi CPU usage giảm
    while [ "$(awk '{print $1}' /proc/loadavg)" > 2 ]; do
        echo "Hệ thống đang tải cao, chờ 5 giây..." | tee -a "$LOG_FILE"
        sleep 5
    done
done

echo "Hoàn tất: Đã mở ${#node_ids[@]} tab gnome-terminal." | tee -a "$LOG_FILE"
echo "Chi tiết log tại $LOG_FILE"
