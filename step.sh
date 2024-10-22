#!/usr/bin/env bash

set -e
set -o pipefail

# Function to check if Telegraf is installed
check_telegraf_installed() {
  if command -v telegraf &> /dev/null; then
    echo "Telegraf is already installed."
  else
    echo "Telegraf is not installed. Installing Telegraf..."
    install_telegraf
  fi
}

# Function to install Telegraf
install_telegraf() {
  if ! command -v brew &> /dev/null; then
    echo "Homebrew is not installed. Please install Homebrew first."
    exit 1
  fi
  
  # Update Homebrew
  brew update

  # Install Telegraf using Homebrew
  brew install telegraf

  echo "Telegraf installation complete."
}

# Function to configure and start Telegraf
start_telegraf() {
  # Create a simple Telegraf configuration file to output metrics to a file
  mkdir -p /Users/vagrant/deploy
  cat << EOF > telegraf.conf
[agent]
  interval = "10s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = ""
  omit_hostname = false
[[outputs.file]]
  files = ["/Users/vagrant/deploy/cpu_metrics.out"]
  data_format = "influx"
  namepass = ["cpu*"]

[[outputs.file]]
  files = ["/Users/vagrant/deploy/mem_metrics.out"]
  data_format = "influx"
  namepass = ["mem*"]

[[inputs.cpu]]
  percpu = true
  totalcpu = true
  fielddrop = ["time_*"]

[[inputs.mem]]
EOF

  # Start Telegraf in the background
  telegraf --config telegraf.conf &
  TELEGRAF_PID=$!

  echo "Telegraf started with PID: $TELEGRAF_PID"
  echo "Telegraf metrics will be written to /Users/vagrant/deploy/telegraf_metrics.out"
}

monitor_and_annotate() {
  sleep 10
  while true; do
    sleep 10
    cpu_lines=$(tail -n $(( $(sysctl -n hw.ncpu) + 1 )) /Users/vagrant/deploy/cpu_metrics.out)

    # Initialize an array to store lines
    to_print=()

    while IFS= read -r line; do
      cpu_label=$(echo "$line" | awk -F'cpu=' '{print $2}' | awk -F',' '{print $1}')
      usage=$(echo "$line" | awk -F'usage_idle=' '{print 100 - $2}' | awk '{print int($1 + 0.5)}')

      bar_length=$((usage / 2))
      empty_length=$((50 - bar_length))

      bar=$(printf '█%.0s' $(seq 1 $bar_length))
      empty_bar=$(printf '░%.0s' $(seq 1 $empty_length))

      # Append the formatted string to the array

      to_print+=("$(printf "\`%s%s\` **%s:** %d%%" "$bar" "$empty_bar" "$cpu_label" "$usage")")
    done <<< "$cpu_lines"

   # Use the joined string in your command

annotation_string=$(cat << EOMESS
## CPU Usage:
$(printf "%s\n\n" "${to_print[@]}")
EOMESS
)
    bitrise :annotations annotate "$annotation_string" --context cpu_usage || true

  done
}

bitrise plugin install https://github.com/bitrise-io/bitrise-plugins-annotations.git

touch /Users/vagrant/deploy/cpu_metrics.out
touch /Users/vagrant/deploy/mem_metrics.out

check_telegraf_installed

sudo pkill -f telegraf || true
start_telegraf

monitor_and_annotate &