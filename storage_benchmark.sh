#!/bin/bash
#
# Copyright (c) 2025. All rights reserved.
#
# Name: storage_benchmark.sh
# Version: 1.1.2
# Author: Mstaaravin
# Contributors: Developed with assistance from Claude AI
# Description: Comprehensive storage device benchmark tool for Linux
#              Performs and compares performance tests across multiple devices
#
# =================================================================
# Linux Storage Benchmark Tool
# =================================================================
#
# DESCRIPTION:
#   This script provides a straightforward interface for benchmarking storage devices
#   on Linux systems. It performs standardized tests including sequential read/write,
#   random read/write, IOPS measurements, and latency tests using the FIO tool.
#   Results are saved in CSV format and visualized with comparative graphs.
#
#   Features include:
#   - Benchmarking multiple storage devices in a single run
#   - Measuring sequential and random read/write performance
#   - Testing IOPS (Input/Output Operations Per Second)
#   - Measuring access latency
#   - Generating comparative graphs between devices
#   - Creating detailed reports in txt and CSV formats
#   - Configurable test parameters via global variables
#
#   The script uses fio for benchmark tests and gnuplot for visualization.
#
# DEPENDENCIES:
#   - fio: Main benchmark tool (apt install fio)
#   - jq: JSON processing (apt install jq)
#   - gnuplot: Optional for graph generation (apt install gnuplot)
#
# CONFIGURATION:
#   The following parameters can be adjusted by modifying the global variables:
#   - SEQ_TEST_SIZE: Size for sequential read/write tests
#   - RAND_TEST_SIZE: Size for random read/write tests
#   - SEQ_BLOCK_SIZE: Block size for sequential operations
#   - RAND_BLOCK_SIZE: Block size for random operations
#   - TEST_RUNTIME: Duration of each test in seconds
#   - USE_DIRECT_IO: Whether to use direct I/O (1) or cached I/O (0)
#   - And more (see Global configuration parameters section)
#
# USAGE:
#   sudo ./storage_benchmark.sh DEVICE_NAME MOUNT_PATH [DEVICE_NAME2 MOUNT_PATH2 ...]
#
# PARAMETERS:
#   DEVICE_NAME    Logical name for the device (e.g., EMMC_32GB, SSD_1TB)
#   MOUNT_PATH     Path to the mount point of the device to test
#
# OPTIONS:
#   Root privileges are recommended for accurate benchmarking (cache clearing)
#
# EXAMPLES:
#   # Benchmark a single eMMC device:
#   sudo ./storage_benchmark.sh EMMC_32GB /home/user/emmc_mount
#
#   # Compare an eMMC device with an HDD:
#   sudo ./storage_benchmark.sh EMMC_32GB /home/user/emmc_mount HDD6TB /archive
#
#   # Compare three different storage devices:
#   sudo ./storage_benchmark.sh EMMC_32GB /mnt/emmc SSD_NVME /mnt/nvme HDD6TB /data
#
# ZFS CONSIDERATIONS:
#   For ZFS filesystems, the ARC cache can significantly impact benchmark results.
#   For more realistic hardware testing, consider:
#   - Temporarily setting primarycache=metadata: sudo zfs set primarycache=metadata pool/dataset
#   - Using larger test sizes (4GB+) to exceed cache size
#   - Running longer tests (30+ seconds) to measure sustained performance
#   - Restore original settings after testing: sudo zfs set primarycache=all pool/dataset
#
# OUTPUTS:
#   The script creates a timestamped directory (benchmark_results_YYYYMMDD_HHMMSS)
#   containing:
#   - Individual JSON files with detailed test results
#   - CSV files with summary data
#   - PNG graph files comparing device performance
#   - benchmark_results_YYYYMMDD_HHMMSS/benchmark_report.txt) A comprehensive text report with test parameters and results
#
# NOTE:
#   For accurate results, ensure that the devices are not heavily used during testing.
#   Root privileges are needed for clearing system caches between tests.
#


# Global configuration parameters
# ===============================

# Test sizes
SEQ_TEST_SIZE="4g"       # Size for sequential tests
RAND_TEST_SIZE="2g"      # Size for random tests
LATENCY_TEST_SIZE="256m" # Size for latency test

# Block sizes
SEQ_BLOCK_SIZE="1m"      # Block size for sequential tests
RAND_BLOCK_SIZE="4k"     # Block size for random tests

# I/O configuration
SEQ_IODEPTH="4"          # I/O depth for sequential tests
RAND_IODEPTH="32"        # I/O depth for random tests
IOPS_IODEPTH="64"        # I/O depth for IOPS test
LATENCY_IODEPTH="1"      # I/O depth for latency test
USE_DIRECT_IO="1"        # Use direct I/O (1=yes, 0=no)

# Job counts
SEQ_JOBS="1"             # Jobs for sequential tests
RAND_JOBS="4"            # Jobs for random tests
IOPS_JOBS="4"            # Jobs for IOPS test
LATENCY_JOBS="1"         # Jobs for latency test

# Runtime parameters
TEST_RUNTIME="10"        # Runtime in seconds for each test

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No color


# Get script version from the version line
get_version() {
    local version_line=$(grep -m 1 "# Version:" "$0")
    SCRIPT_VERSION=$(echo "$version_line" | awk '{print $3}')
    
    # Default version if not found
    if [ -z "$SCRIPT_VERSION" ]; then
        SCRIPT_VERSION="unknown"
    fi
}


# Check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}This script must be run as root for accurate benchmarks!${NC}"
        echo -e "${YELLOW}Running without root privileges will cause some tests to fail.${NC}"
        echo -e "${YELLOW}Please run with: sudo $0 $*${NC}"
        echo ""
        RUNNING_AS_ROOT=0
    else
        RUNNING_AS_ROOT=1
    fi
}

# Check dependencies silently and set availability flags
check_dependencies() {
    # Check fio
    if ! command -v fio &> /dev/null; then
        echo -e "${RED}Error: fio is not installed. Install with: sudo apt install fio${NC}"
        exit 1
    fi

    # Check jq (required for JSON processing)
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is not installed. Install with: sudo apt install jq${NC}"
        exit 1
    fi

    # Check gnuplot (optional)
    if ! command -v gnuplot &> /dev/null; then
        GNUPLOT_AVAILABLE=0
    else
        GNUPLOT_AVAILABLE=1
    fi
}


# Display current benchmark configuration
show_configuration() {
    echo -e "${BLUE}Benchmark Configuration:${NC}"
    echo -e "Sequential tests: ${SEQ_BLOCK_SIZE} blocks, ${SEQ_TEST_SIZE} total, ${SEQ_IODEPTH} IO depth, ${SEQ_JOBS} jobs"
    echo -e "Random tests: ${RAND_BLOCK_SIZE} blocks, ${RAND_TEST_SIZE} total, ${RAND_IODEPTH} IO depth, ${RAND_JOBS} jobs"
    echo -e "IOPS test: ${RAND_BLOCK_SIZE} blocks, ${RAND_TEST_SIZE} total, ${IOPS_IODEPTH} IO depth, ${IOPS_JOBS} jobs"
    echo -e "Latency test: ${RAND_BLOCK_SIZE} blocks, ${LATENCY_TEST_SIZE} total, ${LATENCY_IODEPTH} IO depth, ${LATENCY_JOBS} jobs"
    echo -e "Direct I/O: $([ "$USE_DIRECT_IO" = "1" ] && echo "Enabled" || echo "Disabled")"
    echo -e "Runtime per test: ${TEST_RUNTIME} seconds"
    echo
}

# Function to run a benchmark with fio
run_fio_test() {
    local device_path=$1
    local test_name=$2
    local device_name=$3
    local test_file="${device_path}/benchmark_test_${test_name}.tmp"
    local result_file="$RESULTS_DIR/${device_name}_${test_name}.json"

    echo -e "${BLUE}Running test: ${test_name} on ${device_path}${NC}"

    # Create fio job file
    cat > "/tmp/fio_job_${test_name}.ini" << EOF
[global]
ioengine=libaio
direct=${USE_DIRECT_IO}
time_based=1
runtime=${TEST_RUNTIME}
group_reporting=1

[${test_name}]
name=${test_name}
filename=${test_file}
EOF

    # Add specific parameters based on test type
    case "$test_name" in
        "seq_read")
            echo "rw=read" >> "/tmp/fio_job_${test_name}.ini"
            echo "bs=${SEQ_BLOCK_SIZE}" >> "/tmp/fio_job_${test_name}.ini"
            echo "size=${SEQ_TEST_SIZE}" >> "/tmp/fio_job_${test_name}.ini"
            echo "iodepth=${SEQ_IODEPTH}" >> "/tmp/fio_job_${test_name}.ini"
            echo "numjobs=${SEQ_JOBS}" >> "/tmp/fio_job_${test_name}.ini"
            ;;
        "seq_write")
            echo "rw=write" >> "/tmp/fio_job_${test_name}.ini"
            echo "bs=${SEQ_BLOCK_SIZE}" >> "/tmp/fio_job_${test_name}.ini"
            echo "size=${SEQ_TEST_SIZE}" >> "/tmp/fio_job_${test_name}.ini"
            echo "iodepth=${SEQ_IODEPTH}" >> "/tmp/fio_job_${test_name}.ini"
            echo "numjobs=${SEQ_JOBS}" >> "/tmp/fio_job_${test_name}.ini"
            ;;
        "rand_read")
            echo "rw=randread" >> "/tmp/fio_job_${test_name}.ini"
            echo "bs=${RAND_BLOCK_SIZE}" >> "/tmp/fio_job_${test_name}.ini"
            echo "size=${RAND_TEST_SIZE}" >> "/tmp/fio_job_${test_name}.ini"
            echo "iodepth=${RAND_IODEPTH}" >> "/tmp/fio_job_${test_name}.ini"
            echo "numjobs=${RAND_JOBS}" >> "/tmp/fio_job_${test_name}.ini"
            ;;
        "rand_write")
            echo "rw=randwrite" >> "/tmp/fio_job_${test_name}.ini"
            echo "bs=${RAND_BLOCK_SIZE}" >> "/tmp/fio_job_${test_name}.ini"
            echo "size=${RAND_TEST_SIZE}" >> "/tmp/fio_job_${test_name}.ini"
            echo "iodepth=${RAND_IODEPTH}" >> "/tmp/fio_job_${test_name}.ini"
            echo "numjobs=${RAND_JOBS}" >> "/tmp/fio_job_${test_name}.ini"
            ;;
        "iops_test")
            echo "rw=randread" >> "/tmp/fio_job_${test_name}.ini"
            echo "bs=${RAND_BLOCK_SIZE}" >> "/tmp/fio_job_${test_name}.ini"
            echo "size=${RAND_TEST_SIZE}" >> "/tmp/fio_job_${test_name}.ini"
            echo "iodepth=${IOPS_IODEPTH}" >> "/tmp/fio_job_${test_name}.ini"
            echo "numjobs=${IOPS_JOBS}" >> "/tmp/fio_job_${test_name}.ini"
            ;;
        "latency_test")
            echo "rw=randread" >> "/tmp/fio_job_${test_name}.ini"
            echo "bs=${RAND_BLOCK_SIZE}" >> "/tmp/fio_job_${test_name}.ini"
            echo "size=${LATENCY_TEST_SIZE}" >> "/tmp/fio_job_${test_name}.ini"
            echo "iodepth=${LATENCY_IODEPTH}" >> "/tmp/fio_job_${test_name}.ini"
            echo "numjobs=${LATENCY_JOBS}" >> "/tmp/fio_job_${test_name}.ini"
            ;;
    esac

    # Run fio and save results in JSON format
    fio --output-format=json "/tmp/fio_job_${test_name}.ini" > "$result_file"

    # Extract the main test value and save it to an easy-to-process CSV file
    case "$test_name" in
        "seq_read"|"rand_read")
            local bw=$(jq '.jobs[0].read.bw / 1024' "$result_file")
            echo "${device_name},${test_name},${bw}" >> "$RESULTS_DIR/bandwidth_results.csv"
            ;;
        "seq_write"|"rand_write")
            local bw=$(jq '.jobs[0].write.bw / 1024' "$result_file")
            echo "${device_name},${test_name},${bw}" >> "$RESULTS_DIR/bandwidth_results.csv"
            ;;
        "iops_test")
            local iops=$(jq '.jobs[0].read.iops' "$result_file")
            echo "${device_name},iops,${iops}" >> "$RESULTS_DIR/iops_results.csv"
            ;;
        "latency_test")
            local latency=$(jq '.jobs[0].read.lat_ns.mean / 1000000' "$result_file")
            echo "${device_name},latency,${latency}" >> "$RESULTS_DIR/latency_results.csv"
            ;;
    esac

    # Clean up temporary files
    rm -f "/tmp/fio_job_${test_name}.ini"
    rm -f "$test_file"
}


# Run benchmarks for a device
run_benchmarks() {
    local device_path=$1
    local device_name=$2

    echo -e "\n${GREEN}===== Starting benchmarks for ${device_name} (${device_path}) =====${NC}"

    # Create test directory
    mkdir -p "${device_path}/benchmark_test"

    # Run FIO tests
    run_fio_test "$device_path" "seq_read" "$device_name"
    run_fio_test "$device_path" "seq_write" "$device_name"
    run_fio_test "$device_path" "rand_read" "$device_name"
    run_fio_test "$device_path" "rand_write" "$device_name"
    run_fio_test "$device_path" "iops_test" "$device_name"
    run_fio_test "$device_path" "latency_test" "$device_name"

    # Clean up
    rmdir "${device_path}/benchmark_test"

    echo -e "${GREEN}Benchmark complete for ${device_name}${NC}"
}


# Create plots with gnuplot - DYNAMIC VERSION WITH SINGLE LINE PLOT COMMAND
generate_plots() {
    if [ $GNUPLOT_AVAILABLE -eq 0 ]; then
        echo -e "${YELLOW}Cannot generate graphs, gnuplot is not installed.${NC}"
        return
    fi

    echo -e "${BLUE}Generating graphs...${NC}"

    # Check if we have valid data
    if [ $(wc -l < "$RESULTS_DIR/bandwidth_results.csv") -le 1 ]; then
        echo -e "${YELLOW}Warning: Not enough bandwidth data for plotting.${NC}"
        return
    fi

    # Get all unique device names
    DEVICES=$(awk -F, 'NR>1 {print $1}' "$RESULTS_DIR/bandwidth_results.csv" | sort | uniq)
    NUM_DEVICES=$(echo "$DEVICES" | wc -l)

    # Create a special format file for bandwidth plotting that handles any number of devices
    awk -F, '
        NR==1 {next}  # Skip header
        {
            devices[$1]=1;  # Collect all device names
            if($2=="seq_read") seq_read[$1]=$3; 
            if($2=="seq_write") seq_write[$1]=$3;
            if($2=="rand_read") rand_read[$1]=$3;
            if($2=="rand_write") rand_write[$1]=$3;
        }
        END {
            # Print header with detected device names
            printf "TestType";
            for (dev in devices) {
                printf " %s", dev;
            }
            printf "\n";

            # Print values for each test type
            printf "seq_read";
            for (dev in devices) {
                printf " %s", seq_read[dev] ? seq_read[dev] : "0";
            }
            printf "\n";

            printf "seq_write";
            for (dev in devices) {
                printf " %s", seq_write[dev] ? seq_write[dev] : "0";
            }
            printf "\n";

            printf "rand_read";
            for (dev in devices) {
                printf " %s", rand_read[dev] ? rand_read[dev] : "0";
            }
            printf "\n";

            printf "rand_write";
            for (dev in devices) {
                printf " %s", rand_write[dev] ? rand_write[dev] : "0";
            }
            printf "\n";
        }
    ' "$RESULTS_DIR/bandwidth_results.csv" > "$RESULTS_DIR/bandwidth_plot_data.txt"

    # Create the bandwidth plot script with dynamic device plotting
    cat > "$RESULTS_DIR/bandwidth_plot.gnuplot" << EOF
set terminal pngcairo size 900,600 enhanced font 'Arial,12'
set output '$RESULTS_DIR/bandwidth_comparison.png'
set title 'Bandwidth Comparison (MB/s)\n{/*0.8 Higher is better}'
set style fill solid 0.7 border
set boxwidth 0.8
set xtics rotate by -45
set xlabel 'Test Type'
set ylabel 'MB/s'
set grid ytics
set key outside top right

# Create grouped histogram
set style data histograms
set style histogram clustered gap 1

EOF

    # Define colors manually - no array
    COLOR1="#4169E1"  # Royal Blue
    COLOR2="#DC143C"  # Crimson
    COLOR3="#228B22"  # Forest Green
    COLOR4="#FF8C00"  # Dark Orange
    COLOR5="#9932CC"  # Dark Orchid
    COLOR6="#20B2AA"  # Light Sea Green

    # Construir una sola línea de comando plot sin usar continuaciones de línea
    plot_command="plot "
    i=0
    for dev in $DEVICES; do
        # Use simple if/else for color selection instead of array
        if [ $i -eq 0 ]; then
            color="$COLOR1"
        elif [ $i -eq 1 ]; then
            color="$COLOR2"
        elif [ $i -eq 2 ]; then
            color="$COLOR3"
        elif [ $i -eq 3 ]; then
            color="$COLOR4"
        elif [ $i -eq 4 ]; then
            color="$COLOR5"
        else
            color="$COLOR6"
        fi

        if [ $i -eq 0 ]; then
            plot_command+="'$RESULTS_DIR/bandwidth_plot_data.txt' using $((i+2)):xtic(1) title '$dev' lc rgb '$color'"
        else
            plot_command+=", '$RESULTS_DIR/bandwidth_plot_data.txt' using $((i+2)) title '$dev' lc rgb '$color'"
        fi
        i=$((i+1))
    done

    # Escribir la línea completa del comando plot en el archivo gnuplot
    echo "$plot_command" >> "$RESULTS_DIR/bandwidth_plot.gnuplot"

    # IOPS Plot - Modified for dynamic devices
    cat > "$RESULTS_DIR/iops_plot.gnuplot" << EOF
set terminal pngcairo size 800,600 enhanced font 'Arial,12'
set output '$RESULTS_DIR/iops_comparison.png'
set title 'IOPS Comparison\n{/*0.8 Higher is better}'
set style fill solid 0.7 border
set boxwidth 0.8
set xtics rotate by -45
set xlabel 'Device'
set ylabel 'IOPS'
set grid ytics
set auto y
set datafile separator ','

# Create a better bar chart
set style data histogram
set style histogram cluster gap 1
plot '$RESULTS_DIR/iops_results.csv' every ::1 using 3:xtic(1) title 'IOPS' linecolor rgb '#4169E1'
EOF

    # Latency Plot - Modified for dynamic devices
    cat > "$RESULTS_DIR/latency_plot.gnuplot" << EOF
set terminal pngcairo size 800,600 enhanced font 'Arial,12'
set output '$RESULTS_DIR/latency_comparison.png'
set title 'Latency Comparison (ms)\n{/*0.8 Lower is better}'
set style fill solid 0.7 border
set boxwidth 0.8
set xtics rotate by -45
set xlabel 'Device'
set ylabel 'Latency (ms)'
set grid ytics
set auto y
set datafile separator ','

# Create a better bar chart
set style data histogram
set style histogram cluster gap 1
plot '$RESULTS_DIR/latency_results.csv' every ::1 using 3:xtic(1) title 'Latency' linecolor rgb '#DC143C'
EOF

    # Run gnuplot with error checking
    if gnuplot "$RESULTS_DIR/bandwidth_plot.gnuplot" 2>"$RESULTS_DIR/gnuplot_error.log"; then
        echo -e "${GREEN}Bandwidth graph generated successfully${NC}"
    else
        echo -e "${RED}Error generating bandwidth graph. See $RESULTS_DIR/gnuplot_error.log${NC}"
    fi

    gnuplot "$RESULTS_DIR/iops_plot.gnuplot" 2>/dev/null
    gnuplot "$RESULTS_DIR/latency_plot.gnuplot" 2>/dev/null

    # Check if graphs were created successfully
    if [ -s "$RESULTS_DIR/bandwidth_comparison.png" ] && \
       [ -s "$RESULTS_DIR/iops_comparison.png" ] && \
       [ -s "$RESULTS_DIR/latency_comparison.png" ]; then
        echo -e "${GREEN}All graphs generated in ${RESULTS_DIR}${NC}"
    else
        echo -e "${YELLOW}Warning: Some graphs could not be generated or are empty.${NC}"
    fi
}




# Generate final report
generate_report() {
    echo -e "${BLUE}Generating final report...${NC}"

    # Create report file
    REPORT_FILE="$RESULTS_DIR/benchmark_report.txt"

    {
        echo "==================================================="
        echo "  STORAGE BENCHMARK REPORT"
        echo "  Generated: $(date) (v${SCRIPT_VERSION})"
        echo "==================================================="
        echo ""
        echo "TEST PARAMETERS:"
        echo "----------------------------------"
        echo "Direct I/O: $([ "$USE_DIRECT_IO" = "1" ] && echo "Enabled" || echo "Disabled")"
        echo ""
        echo "Sequential Read:"
        echo "  - Block Size: ${SEQ_BLOCK_SIZE}"
        echo "  - Test Size: ${SEQ_TEST_SIZE}"
        echo "  - I/O Depth: ${SEQ_IODEPTH}"
        echo "  - Jobs: ${SEQ_JOBS}"
        echo "  Description: Measures continuous read performance with large blocks."
        echo ""
        echo "Sequential Write:"
        echo "  - Block Size: ${SEQ_BLOCK_SIZE}"
        echo "  - Test Size: ${SEQ_TEST_SIZE}"
        echo "  - I/O Depth: ${SEQ_IODEPTH}"
        echo "  - Jobs: ${SEQ_JOBS}"
        echo "  Description: Measures continuous write performance with large blocks."
        echo ""
        echo "Random Read:"
        echo "  - Block Size: ${RAND_BLOCK_SIZE}"
        echo "  - Test Size: ${RAND_TEST_SIZE}"
        echo "  - I/O Depth: ${RAND_IODEPTH}"
        echo "  - Jobs: ${RAND_JOBS}"
        echo "  Description: Measures non-sequential small block read performance."
        echo ""
        echo "Random Write:"
        echo "  - Block Size: ${RAND_BLOCK_SIZE}"
        echo "  - Test Size: ${RAND_TEST_SIZE}"
        echo "  - I/O Depth: ${RAND_IODEPTH}"
        echo "  - Jobs: ${RAND_JOBS}"
        echo "  Description: Measures non-sequential small block write performance."
        echo ""
        echo "IOPS Test:"
        echo "  - Block Size: ${RAND_BLOCK_SIZE}"
        echo "  - Test Size: ${RAND_TEST_SIZE}"
        echo "  - I/O Depth: ${IOPS_IODEPTH}"
        echo "  - Jobs: ${IOPS_JOBS}"
        echo "  Description: Measures maximum input/output operations per second."
        echo ""
        echo "Latency Test:"
        echo "  - Block Size: ${RAND_BLOCK_SIZE}"
        echo "  - Test Size: ${LATENCY_TEST_SIZE}"
        echo "  - I/O Depth: ${LATENCY_IODEPTH}"
        echo "  - Jobs: ${LATENCY_JOBS}"
        echo "  Description: Measures time delay between request and response."
        echo ""
        echo "BANDWIDTH RESULTS (MB/s):"
        echo "----------------------------------"
        echo "Device, Test, MB/s"
        cat "$RESULTS_DIR/bandwidth_results.csv"
        echo ""
        echo "IOPS RESULTS:"
        echo "-----------------"
        echo "Device, Test, IOPS"
        cat "$RESULTS_DIR/iops_results.csv"
        echo ""
        echo "LATENCY RESULTS (ms):"
        echo "-------------------------"
        echo "Device, Test, Latency (ms)"
        cat "$RESULTS_DIR/latency_results.csv"
        echo ""
        echo "TERMINOLOGY:"
        echo "---------------------------------------------------"
        echo "Block Size: Size of data chunks read/written in each operation"
        echo "I/O Depth: Number of I/O requests kept in flight at once"
        echo "Jobs: Number of parallel processes performing I/O"
        echo "IOPS: Input/Output Operations Per Second"
        echo "Latency: Time between request submission and completion"
        echo "Sequential: Operations performed on consecutive blocks"
        echo "Random: Operations performed on scattered locations"
        echo "MB/s: Megabytes per second (1 MB = 1,048,576 bytes)"
        echo "ms: Milliseconds (1/1000th of a second)"
        echo "Direct I/O: Bypasses OS page cache (=1) or uses cache (=0)"
    } > "$REPORT_FILE"

    echo -e "${GREEN}Report generated: ${REPORT_FILE}${NC}"

    # Show summary on screen
    echo -e "\n${BLUE}RESULTS SUMMARY:${NC}"
    echo -e "${YELLOW}Bandwidth (MB/s):${NC}"
    cat "$RESULTS_DIR/bandwidth_results.csv"
    echo -e "\n${YELLOW}IOPS:${NC}"
    cat "$RESULTS_DIR/iops_results.csv"
    echo -e "\n${YELLOW}Latency (ms):${NC}"
    cat "$RESULTS_DIR/latency_results.csv"
}




# Main function
main() {
    # Get script version
    get_version
    
    echo -e "${GREEN}=== STORAGE BENCHMARK SCRIPT v${SCRIPT_VERSION} ===${NC}"

    # Check if running as root
    check_root "$@"

    # Check correct arguments were provided
    if [ $# -lt 2 ] || [ $(($# % 2)) -ne 0 ]; then
        echo -e "${RED}Error: Need name:path pairs for each device${NC}"
        echo -e "Usage: $0 name1 path1 name2 path2 [name3 path3 ...]"
        echo -e "Example: $0 EMMC_32GB /mnt/emmc USB_256GB /mnt/usb"
        exit 1
    fi

    # Check dependencies silently
    check_dependencies

    # Display configuration
    show_configuration

    # Create directory for results
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    RESULTS_DIR="benchmark_results_${TIMESTAMP}"
    mkdir -p "$RESULTS_DIR"

    # Initialize CSV files for results
    echo "Device,Test,Value" > "$RESULTS_DIR/bandwidth_results.csv"
    echo "Device,Test,Value" > "$RESULTS_DIR/iops_results.csv"
    echo "Device,Test,Value" > "$RESULTS_DIR/latency_results.csv"

    # Save original arguments
    ALL_ARGS=("$@")
    NUM_ARGS=$#

    # Process each pair of arguments (name and path)
    for ((i=0; i<NUM_ARGS; i+=2)); do
        if [ $((i+1)) -lt $NUM_ARGS ]; then
            device_name=${ALL_ARGS[i]}
            device_path=${ALL_ARGS[i+1]}

            # Check if path exists
            if [ ! -d "$device_path" ]; then
                echo -e "${RED}Error: Path $device_path does not exist or is not accessible${NC}"
                continue
            fi

            # Check write permissions
            if [ ! -w "$device_path" ]; then
                echo -e "${RED}Error: You don't have write permissions on $device_path${NC}"
                continue
            fi

            # Run benchmarks
            run_benchmarks "$device_path" "$device_name"
        fi
    done

    # Generate plots
    generate_plots

    # Generate report
    generate_report

    echo -e "\n${GREEN}All benchmarks completed. Results in ${RESULTS_DIR}${NC}"
}


# Run main function with all arguments
main "$@"
