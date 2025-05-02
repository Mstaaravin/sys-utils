#!/bin/bash
#
# Copyright (c) 2025. All rights reserved.
#
# Script: compare_benchmarks_simple.sh
# Description: Compare results from multiple benchmark directories with different device names
# Author: Mstaaravin
# Contributors: Developed with assistance from Claude AI
# Version: 1.0.0
#
# =================================================================
# Multi-Benchmark Comparison Tool
# =================================================================
#
# DESCRIPTION:
#   This script provides a tool for comparing results from multiple storage
#   benchmark directories. It extracts data from benchmark result files
#   (JSON and CSV) and generates comparative visualizations showing performance
#   differences between multiple storage devices.
#
#   Features include:
#   - Automatic detection of devices across multiple benchmark directories
#   - Support for complex device names including underscores
#   - Generation of comparative performance graphs (bandwidth, IOPS, latency)
#   - Customizable device order and display names
#   - Compatible with standard gnuplot installations
#
# DEPENDENCIES:
#   - gnuplot: Required for graph generation (apt install gnuplot)
#
# USAGE:
#   ./compare_benchmarks.sh [options] DIRECTORY1 DIRECTORY2 [DIRECTORY3 ...]
#
# OPTIONS:
#   -h, --help               Display usage information
#   -o, --output DIR         Set output directory (default: ./comparison_results)
#   -d, --devices DEV1,DEV2  Specify device order (comma separated list)
#   -s, --sort [alpha|param] Sort devices alphabetically or by parameter order
#   -n, --names NAME1,NAME2  Custom display names for devices (comma separated list)
#
# EXAMPLES:
#   # Compare two benchmark result directories:
#   ./compare_benchmarks.sh benchmark_results_20250502_153056 benchmark_results_20250502_154553
#
#   # Compare with custom output directory:
#   ./compare_benchmarks.sh -o my_comparison benchmark_results_1 benchmark_results_2
#
#   # Compare with custom device order and names:
#   ./compare_benchmarks.sh -d "SSD,HDD,USB" -n "SSD Drive,HDD Drive,USB Stick" dir1 dir2 dir3
#
# NOTES:
#   - This tool is complementary to the storage_benchmark.sh script
#   - Each benchmark directory should contain standard benchmark result files
#     (bandwidth_results.csv, iops_results.csv, latency_results.csv)
#   - The script will identify devices by their naming patterns in JSON/CSV files
#


# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No color

# Function to show usage
show_usage() {
    echo "Usage: $0 [options] [directories...]"
    echo ""
    echo "Compare benchmark results across multiple directories."
    echo "Each directory should contain benchmark results for different devices."
    echo ""
    echo "Example:"
    echo "  $0 benchmark_results_20250502_144531 benchmark_results_20250502_145855"
    echo ""
    echo "Options:"
    echo "  -h, --help               Display this help message"
    echo "  -o, --output DIR         Set output directory (default: ./comparison_results)"
    echo "  -d, --devices DEV1,DEV2  Specify device order (comma separated list)"
    echo "  -s, --sort [alpha|param] Sort devices alphabetically or by parameter order (default: param)"
    echo "  -n, --names NAME1,NAME2  Custom display names for devices (comma separated list)"
    echo ""
}

# Default output directory and sorting
OUTPUT_DIR="./comparison_results"
SORT_METHOD="param"  # Can be 'alpha' or 'param'
CUSTOM_DEVICES=""
CUSTOM_NAMES=""

# Parse arguments
DIRS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -d|--devices)
            CUSTOM_DEVICES="$2"
            shift 2
            ;;
        -n|--names)
            CUSTOM_NAMES="$2"
            shift 2
            ;;
        -s|--sort)
            if [[ "$2" == "alpha" || "$2" == "param" ]]; then
                SORT_METHOD="$2"
                shift 2
            else
                echo -e "${RED}Error: Sort method must be 'alpha' or 'param'${NC}"
                show_usage
                exit 1
            fi
            ;;
        -*)
            echo -e "${RED}Error: Unknown option $1${NC}"
            show_usage
            exit 1
            ;;
        *)
            # Add to directories array
            DIRS+=("$1")
            shift
            ;;
    esac
done

# Check if we have any directories
if [ ${#DIRS[@]} -eq 0 ]; then
    echo -e "${RED}Error: No benchmark directories provided${NC}"
    show_usage
    exit 1
fi

# Check if gnuplot is installed
if ! command -v gnuplot &> /dev/null; then
    echo -e "${RED}Error: gnuplot is not installed. Install with: sudo apt install gnuplot${NC}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Function to collect device names from a directory
collect_devices() {
    local dir="$1"
    local device_list=()
    
    # Look for JSON files with test types
    find "$dir" -name "*.json" | while read -r file; do
        filename=$(basename "$file")
        for test_type in "_seq_read.json" "_seq_write.json" "_rand_read.json" "_rand_write.json" "_iops_test.json" "_latency_test.json"; do
            if [[ "$filename" == *"$test_type" ]]; then
                # Get device name by removing the test type suffix
                device="${filename%$test_type}"
                if ! [[ " ${device_list[*]} " =~ " ${device} " ]]; then
                    device_list+=("$device")
                    echo "$device"
                fi
                break
            fi
        done
    done
    
    # If no devices found from JSON files, try CSV files
    if [ ${#device_list[@]} -eq 0 ] && [ -f "$dir/bandwidth_results.csv" ]; then
        # Extract device names from first column (skip header)
        tail -n +2 "$dir/bandwidth_results.csv" | cut -d',' -f1 | sort -u
    fi
}

# Function to extract the file pattern for a device
get_file_pattern() {
    local dir="$1"
    local device="$2"
    
    # Try to find a JSON file for this device
    for file in "$dir"/*; do
        if [[ -f "$file" && "$file" == *"${device}_"*".json" ]]; then
            # Extract the pattern used in filenames
            pattern="${device}"
            echo "$pattern"
            return
        fi
    done
    
    # If not found, just return the device name
    echo "$device"
}

# Function to extract bandwidth data for a device from a directory
extract_bandwidth_data() {
    local dir="$1"
    local device="$2"
    local display_name="$3"
    local data_file="$4"
    local index="$5"  # Device index for ordering in the plot
    
    # Get the file pattern for this device
    pattern=$(get_file_pattern "$dir" "$device")
    
    if [ -f "$dir/bandwidth_results.csv" ]; then
        # Extract data for this device
        grep "^${pattern}," "$dir/bandwidth_results.csv" | \
            awk -v dev="$display_name" -v idx="$index" -F',' \
            '{print dev","$2","$3","idx}' >> "$data_file"
    else
        echo -e "${YELLOW}Warning: No bandwidth_results.csv found in $dir${NC}"
    fi
}

# Function to extract IOPS data for a device from a directory
extract_iops_data() {
    local dir="$1"
    local device="$2"
    local display_name="$3"
    local data_file="$4"
    local index="$5"  # Device index for ordering in the plot
    
    # Get the file pattern for this device
    pattern=$(get_file_pattern "$dir" "$device")
    
    if [ -f "$dir/iops_results.csv" ]; then
        # Extract data for this device
        grep "^${pattern}," "$dir/iops_results.csv" | \
            awk -v dev="$display_name" -v idx="$index" -F',' \
            '{print dev","$3","idx}' >> "$data_file"
    else
        echo -e "${YELLOW}Warning: No iops_results.csv found in $dir${NC}"
    fi
}

# Function to extract latency data for a device from a directory
extract_latency_data() {
    local dir="$1"
    local device="$2"
    local display_name="$3"
    local data_file="$4"
    local index="$5"  # Device index for ordering in the plot
    
    # Get the file pattern for this device
    pattern=$(get_file_pattern "$dir" "$device")
    
    if [ -f "$dir/latency_results.csv" ]; then
        # Extract data for this device
        grep "^${pattern}," "$dir/latency_results.csv" | \
            awk -v dev="$display_name" -v idx="$index" -F',' \
            '{print dev","$3","idx}' >> "$data_file"
    else
        echo -e "${YELLOW}Warning: No latency_results.csv found in $dir${NC}"
    fi
}

# Collect all unique devices from all directories
ALL_DEVICES=()
DEVICE_ORDER=()  # To maintain the order of directories as passed

for dir in "${DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo -e "${RED}Error: Directory $dir does not exist${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Scanning directory: $dir${NC}"
    mapfile -t devices < <(collect_devices "$dir")
    
    # Store the devices in the order they were found for this directory
    for device in "${devices[@]}"; do
        # Skip empty devices
        if [ -z "$device" ]; then
            continue
        fi
        
        # Add to the master list if not already there
        if ! [[ " ${ALL_DEVICES[*]} " =~ " ${device} " ]]; then
            ALL_DEVICES+=("$device")
            echo "  Found device: $device"
        fi
        
        # Add to ordered list with source directory (for parameter-order sorting)
        DEVICE_ORDER+=("$device:$dir")
    done
done

if [ ${#ALL_DEVICES[@]} -eq 0 ]; then
    echo -e "${RED}Error: No devices found in the provided directories${NC}"
    exit 1
fi

echo -e "${GREEN}Found ${#ALL_DEVICES[@]} unique devices across ${#DIRS[@]} directories${NC}"

# Sort devices based on the selected method
SORTED_DEVICES=()

if [ -n "$CUSTOM_DEVICES" ]; then
    # User provided a custom device order
    echo -e "${BLUE}Using custom device order${NC}"
    IFS=',' read -ra SORTED_DEVICES <<< "$CUSTOM_DEVICES"
    
    # Verify all devices exist
    for dev in "${SORTED_DEVICES[@]}"; do
        if ! [[ " ${ALL_DEVICES[*]} " =~ " ${dev} " ]]; then
            echo -e "${YELLOW}Warning: Custom device '$dev' not found in benchmark data${NC}"
        fi
    done
    
    # Add any devices that weren't in the custom list to the end
    for dev in "${ALL_DEVICES[@]}"; do
        if ! [[ " ${SORTED_DEVICES[*]} " =~ " ${dev} " ]]; then
            SORTED_DEVICES+=("$dev")
        fi
    done
    
elif [ "$SORT_METHOD" = "alpha" ]; then
    # Alphabetical sort
    echo -e "${BLUE}Sorting devices alphabetically${NC}"
    SORTED_DEVICES=($(printf '%s\n' "${ALL_DEVICES[@]}" | sort))
else
    # Parameter order (default) - maintain the order devices were discovered in directories
    echo -e "${BLUE}Sorting devices by parameter order${NC}"
    
    # Create a unique ordered list preserving the first occurrence order
    declare -A seen_devices
    for entry in "${DEVICE_ORDER[@]}"; do
        # Extract just the device name
        device=$(echo "$entry" | cut -d':' -f1)
        
        if [[ -z "${seen_devices[$device]}" ]]; then
            SORTED_DEVICES+=("$device")
            seen_devices[$device]=1
        fi
    done
fi

# Prepare display names
DISPLAY_NAMES=()

if [ -n "$CUSTOM_NAMES" ]; then
    # User provided custom display names
    IFS=',' read -ra DISPLAY_NAMES <<< "$CUSTOM_NAMES"
    
    # If we have fewer display names than devices, use device names for the rest
    if [ ${#DISPLAY_NAMES[@]} -lt ${#SORTED_DEVICES[@]} ]; then
        for ((i=${#DISPLAY_NAMES[@]}; i<${#SORTED_DEVICES[@]}; i++)); do
            DISPLAY_NAMES+=("${SORTED_DEVICES[i]}")
        done
    fi
else
    # Use the device names as display names (remove any directory prefixes)
    for device in "${SORTED_DEVICES[@]}"; do
        # Extract just the device name without any directory structure
        simple_name=$(basename "$device")
        DISPLAY_NAMES+=("$simple_name")
    done
fi

# Display the final order
echo -e "${BLUE}Device order for plots:${NC}"
for i in "${!SORTED_DEVICES[@]}"; do
    echo "  $((i+1)). ${SORTED_DEVICES[i]} (Display: ${DISPLAY_NAMES[i]})"
done

# Create data files for each metric
BANDWIDTH_DATA="$OUTPUT_DIR/bandwidth_data.csv"
IOPS_DATA="$OUTPUT_DIR/iops_data.csv"
LATENCY_DATA="$OUTPUT_DIR/latency_data.csv"

# Initialize with headers
echo "Device,Test,Value,Index" > "$BANDWIDTH_DATA"
echo "Device,Value,Index" > "$IOPS_DATA"
echo "Device,Value,Index" > "$LATENCY_DATA"

# Extract data for each device from each directory
# We'll use the sorted device list to ensure consistent order
for index in "${!SORTED_DEVICES[@]}"; do
    device="${SORTED_DEVICES[$index]}"
    display_name="${DISPLAY_NAMES[$index]}"
    device_index=$((index+1))
    
    for dir in "${DIRS[@]}"; do
        # Check if the device exists in this directory
        if [ -f "$dir/bandwidth_results.csv" ] && grep -q "^${device}," "$dir/bandwidth_results.csv" || \
           find "$dir" -name "${device}_*.json" -print -quit | grep -q .; then
            echo -e "${BLUE}Extracting data for $device from $(basename "$dir")${NC}"
            extract_bandwidth_data "$dir" "$device" "$display_name" "$BANDWIDTH_DATA" "$device_index"
            extract_iops_data "$dir" "$device" "$display_name" "$IOPS_DATA" "$device_index"
            extract_latency_data "$dir" "$device" "$display_name" "$LATENCY_DATA" "$device_index"
        fi
    done
done

# Define a color palette with distinct colors
COLORS=(
    "blue"            # Blue
    "red"             # Red
    "forest-green"    # Green
    "orange"          # Orange
    "violet"          # Purple
    "turquoise"       # Turquoise
    "brown"           # Brown
    "gold"            # Gold
    "black"           # Black
    "gray"            # Gray
    "pink"            # Pink
    "dark-blue"       # Dark Blue
    "dark-red"        # Dark Red
    "olive"           # Olive
    "cyan"            # Cyan
    "magenta"         # Magenta
    "yellow"          # Yellow
    "dark-gray"       # Dark Gray
)

# Create a simpler version that will surely work with all gnuplot versions

# Create single files for each test type
mkdir -p "$OUTPUT_DIR/data"

# For bandwidth - create separate files for each test type (seq_read, seq_write, etc.)
echo "Device SeqRead SeqWrite RandRead RandWrite" > "$OUTPUT_DIR/data/bandwidth.dat"
for device in "${DISPLAY_NAMES[@]}"; do
    # Initialize values
    seq_read="0"
    seq_write="0"
    rand_read="0"
    rand_write="0"
    
    # Get values from bandwidth_data.csv
    if [ -f "$BANDWIDTH_DATA" ]; then
        while IFS=, read -r dev test value index; do
            if [ "$dev" = "$device" ]; then
                case "$test" in
                    "seq_read") seq_read="$value" ;;
                    "seq_write") seq_write="$value" ;;
                    "rand_read") rand_read="$value" ;;
                    "rand_write") rand_write="$value" ;;
                esac
            fi
        done < "$BANDWIDTH_DATA"
    fi
    
    # Write to file
    echo "$device $seq_read $seq_write $rand_read $rand_write" >> "$OUTPUT_DIR/data/bandwidth.dat"
done

# For IOPS - create separate file
echo "Device IOPS" > "$OUTPUT_DIR/data/iops.dat"
if [ -f "$IOPS_DATA" ]; then
    while IFS=, read -r device value index; do
        if [ "$device" != "Device" ]; then  # Skip header
            echo "$device $value" >> "$OUTPUT_DIR/data/iops.dat"
        fi
    done < "$IOPS_DATA"
fi

# For Latency - create separate file
echo "Device Latency" > "$OUTPUT_DIR/data/latency.dat"
if [ -f "$LATENCY_DATA" ]; then
    while IFS=, read -r device value index; do
        if [ "$device" != "Device" ]; then  # Skip header
            echo "$device $value" >> "$OUTPUT_DIR/data/latency.dat"
        fi
    done < "$LATENCY_DATA"
fi

# Create simple gnuplot scripts
cat > "$OUTPUT_DIR/bandwidth_plot.gnuplot" << EOF
set terminal pngcairo size 1200,800 enhanced font 'Arial,12'
set output '$OUTPUT_DIR/bandwidth_comparison.png'
set title 'Bandwidth Comparison (MB/s)\n {/*0.8 Higher is better}'
set style data histograms
set style histogram clustered gap 1
set style fill solid 0.7 border -1
set boxwidth 0.9
set grid ytics
set key outside right top vertical
set xlabel 'Device'
set ylabel 'MB/s'
set xtics rotate by -45
set yrange [0:*]
set auto x

plot '$OUTPUT_DIR/data/bandwidth.dat' using 2:xtic(1) title 'Sequential Read', \
     '' using 3 title 'Sequential Write', \
     '' using 4 title 'Random Read', \
     '' using 5 title 'Random Write'
EOF

cat > "$OUTPUT_DIR/iops_plot.gnuplot" << EOF
set terminal pngcairo size 1000,700 enhanced font 'Arial,12'
set output '$OUTPUT_DIR/iops_comparison.png'
set title 'IOPS Comparison\n {/*0.8 Higher is better}'
set style data histograms
set style histogram clustered gap 1
set style fill solid 0.7 border -1
set boxwidth 0.9
set grid ytics
set key outside right top vertical
set xlabel 'Device'
set ylabel 'IOPS'
set xtics rotate by -45
set yrange [0:*]
set auto x

plot '$OUTPUT_DIR/data/iops.dat' using 2:xtic(1) title 'IOPS' linecolor rgb "blue"
EOF

cat > "$OUTPUT_DIR/latency_plot.gnuplot" << EOF
set terminal pngcairo size 1000,700 enhanced font 'Arial,12'
set output '$OUTPUT_DIR/latency_comparison.png'
set title 'Latency Comparison (ms)\n {/*0.8 Lower is better}'
set style data histograms
set style histogram clustered gap 1
set style fill solid 0.7 border -1
set boxwidth 0.9
set grid ytics
set key outside right top vertical
set xlabel 'Device'
set ylabel 'Latency (ms)'
set xtics rotate by -45
set yrange [0:*]
set auto x

plot '$OUTPUT_DIR/data/latency.dat' using 2:xtic(1) title 'Latency' linecolor rgb "red"
EOF

# Run gnuplot scripts
echo -e "${BLUE}Generating bandwidth comparison plot...${NC}"
if gnuplot "$OUTPUT_DIR/bandwidth_plot.gnuplot" 2>"$OUTPUT_DIR/bandwidth_gnuplot.log"; then
    echo -e "${GREEN}Bandwidth plot generated: $OUTPUT_DIR/bandwidth_comparison.png${NC}"
else
    echo -e "${RED}Error generating bandwidth plot${NC}"
    echo "Check the log at $OUTPUT_DIR/bandwidth_gnuplot.log and script at $OUTPUT_DIR/bandwidth_plot.gnuplot"
    cat "$OUTPUT_DIR/bandwidth_gnuplot.log"
fi

echo -e "${BLUE}Generating IOPS comparison plot...${NC}"
if gnuplot "$OUTPUT_DIR/iops_plot.gnuplot" 2>"$OUTPUT_DIR/iops_gnuplot.log"; then
    echo -e "${GREEN}IOPS plot generated: $OUTPUT_DIR/iops_comparison.png${NC}"
else
    echo -e "${RED}Error generating IOPS plot${NC}"
    echo "Check the log at $OUTPUT_DIR/iops_gnuplot.log and script at $OUTPUT_DIR/iops_plot.gnuplot"
    cat "$OUTPUT_DIR/iops_gnuplot.log"
fi

echo -e "${BLUE}Generating latency comparison plot...${NC}"
if gnuplot "$OUTPUT_DIR/latency_plot.gnuplot" 2>"$OUTPUT_DIR/latency_gnuplot.log"; then
    echo -e "${GREEN}Latency plot generated: $OUTPUT_DIR/latency_comparison.png${NC}"
else
    echo -e "${RED}Error generating latency plot${NC}"
    echo "Check the log at $OUTPUT_DIR/latency_gnuplot.log and script at $OUTPUT_DIR/latency_plot.gnuplot"
    cat "$OUTPUT_DIR/latency_gnuplot.log"
fi

echo -e "${GREEN}All comparisons complete. Results in ${OUTPUT_DIR}${NC}"
echo "Generated files:"
echo "  - $OUTPUT_DIR/bandwidth_comparison.png"
echo "  - $OUTPUT_DIR/iops_comparison.png"
echo "  - $OUTPUT_DIR/latency_comparison.png"
echo "  - Data files and gnuplot scripts in $OUTPUT_DIR"
