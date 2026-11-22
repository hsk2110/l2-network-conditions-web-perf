#!/bin/bash
#set -ex
if [[ ${EUID} -ne 0 ]]; then
	echo "$0 is not running as root. Try using sudo."
	exit 2
fi

# iperf start:
iperfReference () {
  # iperf (UDP mode; 1Gbit; ul/dl separat messen) test der als referenz dient
  # muss 1x pro environment laufen
  touch "${TEST_DIR}/iperf_server.log"
  touch "${TEST_DIR}/iperf_client.log"
  touch "${TEST_DIR}/iperf_traffic.pcap"
  # for singled out testing:
  ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms  
  
  # start capturing
  # ip netns exec bottleneck-net tcpdump -s 100 -G 3600 -i br-client-inet -w "${TEST_DIR}/iperf_traffic.pcap" 2> /tmp/tcpdump.log &
  # TCPDUMP_PID=$!

  ip netns exec server-net iperf3 -s -B 10.237.0.3 > "${TEST_DIR}/iperf_server.log" 2>&1 &
  SERVER_PID=$!

  sleep 0.5

  echo "client iperf3" >> "${TEST_DIR}/iperf_client.log"
  ip netns exec client-net iperf3 -c 10.237.0.3 -t 15 -u -b 1G >> "${TEST_DIR}/iperf_client.log" 2>&1
  echo "client iperf3 reverse" >> "${TEST_DIR}/iperf_client.log"
  ip netns exec client-net iperf3 -c 10.237.0.3 -R -t 15 -u -b 1G >> "${TEST_DIR}/iperf_client.log" 2>&1

  
  kill -SIGINT $SERVER_PID
  wait $SERVER_PID
  echo "iperf3 killed."
  # kill -SIGINT $TCPDUMP_PID
  # wait $TCPDUMP_PID
  # echo "tcpdump killed."
  
  ./setup-shaping.sh DELETE
}

# building of parameter string that consists of all combinations from testparameters.txt
declare -a PARAMETER_COMBINATIONS=()
declare -a PARAMETER_DIRECTORIES=()

build_parameter_array() {
  PARAMETER_COMBINATIONS=()
  PARAMETER_DIRECTORIES=()

  local -a names mins maxes steps current
  local name min max step
  local i combination directory_name carry next

  while read -r name min max step || [[ -n "$name" ]]; do
    [[ -z "$name" || "$name" == \#* || "$name" == "default" ]] && continue

    names+=("$name")
    mins+=("$min")
    maxes+=("$max")
    steps+=("$step")
    current+=("$min")
  done < rpmparameters/testparameters.txt

  while :; do
    combination=""
    directory_name=""

    for ((i = 0; i < ${#names[@]}; i++)); do
      combination+="--rpm.${names[i]} ${current[i]} "
      directory_name+="${names[i]}=${current[i]}__"
    done

    PARAMETER_COMBINATIONS+=("${combination% }")
    PARAMETER_DIRECTORIES+=("${directory_name%__}")

    carry=1

    for ((i = ${#names[@]} - 1; i >= 0 && carry; i--)); do
      next=$(bc -l <<< "${current[i]} + ${steps[i]}")

      if [[ "$(bc -l <<< "$next <= ${maxes[i]}")" == "1" ]]; then
        current[i]="$next"
        carry=0
      else
        current[i]="${mins[i]}"
      fi
    done

    (( carry )) && break
  done
}

# single dimensional iteration through test parameters
iterParameters () {

  starttime=$(date +%d-%m-%Y_%H-%M-%S)
  # first we make a directory for the whole measurement:
  # MEASUREMENT_DIR="outputfiles/measurement_$(date +%d-%m-%Y_%H-%M-%S)"
  # if on the server:
  MEASUREMENT_DIR="/data/rpm_measurements/measurement_$(date +%d-%m-%Y_%H-%M-%S)"
  mkdir "${MEASUREMENT_DIR}"
  touch "${MEASUREMENT_DIR}/progress.log"

  # define client command:
  local -a networkQualityCommand=(
    ip netns exec client-net
    ./networkQuality
    --connect-to 10.237.0.3
    --insecure-skip-verify
    --relative-rpm
    --extended-stats
  )

  # loop over the environments (environment-name, capacities and delay in both directions)
  while IFS= read -r line || [ -n "${line}" ]; do    
    read -r envname dl_capacity ul_capacity dl_delay_from_inet ul_delay_to_inet <<< "${line}" # read the environment parameters
    mkdir "${MEASUREMENT_DIR}/${envname}"
    # loop over the test-parameters (parameter-name, minimum and maximum value and iteration steps)  
    while IFS= read -r line || [ -n "$line" ]; do
      read -r test_parameter p_min p_max steps <<< "$line" # read the test parameter values, min, max and steps
      i=$p_min
      TEST_DIR="${MEASUREMENT_DIR}/${envname}/${test_parameter}"
      mkdir "${TEST_DIR}"      
      # if parameter is a float
      if [[ "${test_parameter}" = "ptc" ]]; then        
        # loop over the currently tested parameter
        # 1. emulation start
        # 2. server start
        # 3. wait until server reachable
        # 4. client start
        # (4. Client's output gets logged)
        # 5. server and emulation shutdown
        while [ "$(bc <<< "$i <= $p_max")" == "1"  ]; do
          mkdir "${TEST_DIR}/At${i}"                    
          # we do 100 iterations
          for j in {1..100}; do
            echo "currently: ${envname}_${test_parameter}_at${i}_iteration${j}" > "${MEASUREMENT_DIR}/progress.log"
            mkdir "${TEST_DIR}/At${i}/${j}"
            TEST_FILE="${TEST_DIR}/At${i}/${j}/test_output.log"
            PCAP_FILE="${TEST_DIR}/At${i}/${j}/traffic.pcap"
            KEYS_FILE="${TEST_DIR}/At${i}/${j}/test_keys.keys"
            SERVER_FILE="${TEST_DIR}/At${i}/${j}/server_output.log"
            touch ${TEST_FILE}
            cat /dev/null > ${TEST_FILE}          
            ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
            
            # start capturing packets
            ip netns exec bottleneck-net tcpdump -s 100 -i br-client-inet -w "${PCAP_FILE}" 2> /tmp/tcpdump.log  &
            TCPDUMP_PID=$!
            
            # start server and get pid for killing later
            ip netns exec server-net ./networkqualityd -create-cert --listen-addr 10.237.0.3 \
              >${SERVER_FILE} 2>&1 &
            SERVER_PID=$!
            
            # Wait until the server port is reachable
            ip netns exec client-net bash -c '
              for i in {1..300}; do
                timeout 0.2 bash -c "</dev/tcp/10.237.0.3/4043" >/dev/null 2>&1 && exit 0
                sleep 0.02
              done
              echo "Timed out waiting for 10.237.0.3:4043 from client-net" >&2
              exit 1
            ' || { kill "$SERVER_PID" 2>/dev/null || true; ./setup-shaping.sh DELETE; exit 1; }
            
            # log the set test parameters into output
            echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> ${TEST_FILE}
            echo "Testing test parameter ${test_parameter} ${i}" >> ${TEST_FILE}
            echo "iteration ${j}" >> ${TEST_FILE} 

            # start client and log it into output
            "${networkQualityCommand[@]}" \
              "--rpm.${test_parameter}" "${i}" \
              >> "$TEST_FILE"

            # kill server and tcpdump and delete network
            kill "$SERVER_PID" 2>/dev/null || true
            wait "$SERVER_PID" 2>/dev/null || true
            kill "$TCPDUMP_PID" 2>/dev/null || true
            wait "$TCPDUMP_PID" 2>/dev/null || true
            ./setup-shaping.sh DELETE
            done
          i=$(echo "$i + $steps" | bc -l)    
        done
      elif [[ "${test_parameter}" = "default" ]]; then # default means we use default parameter values
        # if we do a default iteration
        # 1. emulation start
        # 2. server start
        # 3. wait until server reachable
        # 4. client start
        # (4. Client's output gets logged)
        # 5. server and emulation shutdown
        iperfReference
        #  we do 100 iterations
        for j in {1..100}; do
          echo "currently: ${envname}_${test_parameter}_iteration${j}" > "${MEASUREMENT_DIR}/progress.log" 
          mkdir "${TEST_DIR}/${j}"
          TEST_FILE="${TEST_DIR}/${j}/test_output.log"
          PCAP_FILE="${TEST_DIR}/${j}/traffic.pcap"
          KEYS_FILE="${TEST_DIR}/${j}/keys.log"
          SERVER_FILE="${TEST_DIR}/${j}/server_output.log"
          touch ${TEST_FILE}
          cat /dev/null > ${TEST_FILE}              
          ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
          
          # start capturing packets
          ip netns exec bottleneck-net tcpdump -s 100 -i br-client-inet -w "${PCAP_FILE}" 2> /tmp/tcpdump.log  &
          TCPDUMP_PID=$!
          
          # start server and get pid for killing later
          ip netns exec server-net ./networkqualityd --create-cert --listen-addr 10.237.0.3 \
            >${SERVER_FILE} 2>&1 &
          SERVER_PID=$!

          # Wait until the server port is reachable
          ip netns exec client-net bash -c '
            for i in {1..300}; do
              timeout 0.2 bash -c "</dev/tcp/10.237.0.3/4043" >/dev/null 2>&1 && exit 0
              sleep 0.02
            done
            echo "Timed out waiting for 10.237.0.3:4043 from client-net" >&2
            exit 1
          ' || { kill "$SERVER_PID" 2>/dev/null || true; ./setup-shaping.sh DELETE; exit 1; }

          # log the set test parameters into output
          echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> ${TEST_FILE}
		      echo "iteration ${j}" >> ${TEST_FILE}
 
          # start client and log it into output
          "${networkQualityCommand[@]}" \
              >> "$TEST_FILE"

          # kill server and tcpdump and delete network
          kill "$SERVER_PID" 2>/dev/null || true
          wait "$SERVER_PID" 2>/dev/null || true
          kill "$TCPDUMP_PID" 2>/dev/null || true
          wait "$TCPDUMP_PID" 2>/dev/null || true
          ./setup-shaping.sh DELETE

        done
      else
        # for integers
        # 1. emulation start
        # 2. server start
        # 3. wait until server reachable
        # 4. client start
        # (4. Client's output gets logged)
        # 5. server and emulation shutdown
        while (( i <= p_max )); do
          mkdir "${TEST_DIR}/At${i}"
          #  we do 100 iterations
          for j in {1..100}; do
            echo "currently: ${envname}_${test_parameter}_at${i}_iteration${j}" > "${MEASUREMENT_DIR}/progress.log" 
            mkdir "${TEST_DIR}/At${i}/${j}"
            TEST_FILE="${TEST_DIR}/At${i}/${j}/test_output.log"
            PCAP_FILE="${TEST_DIR}/At${i}/${j}/traffic.pcap"
            KEYS_FILE="${TEST_DIR}/At${i}/${j}/test_keys.keys"
            SERVER_FILE="${TEST_DIR}/At${i}/${j}/server_output.log"
            touch ${TEST_FILE}
            cat /dev/null > ${TEST_FILE}
            ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
            
            # start capturing packets
            ip netns exec bottleneck-net tcpdump -s 100 -i br-client-inet -w "${PCAP_FILE}" 2> /tmp/tcpdump.log  &
            TCPDUMP_PID=$!
            
            # start server and get pid for killing later
            ip netns exec server-net ./networkqualityd -create-cert --listen-addr 10.237.0.3 \
              >${SERVER_FILE} 2>&1 &
            SERVER_PID=$!
            # Wait until the server port is reachable
            ip netns exec client-net bash -c '
              for i in {1..300}; do
                timeout 0.2 bash -c "</dev/tcp/10.237.0.3/4043" >/dev/null 2>&1 && exit 0
                sleep 0.02
              done
              echo "Timed out waiting for 10.237.0.3:4043 from client-net" >&2
              exit 1
            ' || { kill "$SERVER_PID" 2>/dev/null || true; ./setup-shaping.sh DELETE; exit 1; }

            # log the set test parameters into output
            echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> ${TEST_FILE}
            echo "Testing test parameter ${test_parameter} ${i}" >> ${TEST_FILE}
            echo "iteration ${j}" >> ${TEST_FILE}

            # start client and log it into output
            # HAVE EDITED IT FOR TWO DIM EDIT IT OUT LATER
            "${networkQualityCommand[@]}" \
              "--rpm.${test_parameter}" "${i}" \
              >> "$TEST_FILE"

            # kill server and delete network
            kill "$SERVER_PID" 2>/dev/null || true
            wait "$SERVER_PID" 2>/dev/null || true
            kill "$TCPDUMP_PID" 2>/dev/null || true
            wait "$TCPDUMP_PID" 2>/dev/null || true
            ./setup-shaping.sh DELETE
          done    
          ((i+=steps))
        done 
      fi 
    done < rpmparameters/testparameters.txt
  done < rpmparameters/environments.txt
  endtime=$(date +%d-%m-%Y_%H-%M-%S)
  {
    echo "test done"
    echo "started at: ${starttime}"
    echo "ended at: ${endtime}"
  } > "${MEASUREMENT_DIR}/progress.log"
}


# multi dimensional iteration through test parameters
iterParametersMulti () {
  starttime=$(date +%d-%m-%Y_%H-%M-%S)
  # first we make a directory for the whole measurement:
  # MEASUREMENT_DIR="outputfiles/measurement_$(date +%d-%m-%Y_%H-%M-%S)"
  # if on the server:
  MEASUREMENT_DIR="/data/rpm_measurements/measurement_$(date +%d-%m-%Y_%H-%M-%S)"
  mkdir -p "${MEASUREMENT_DIR}"
  touch "${MEASUREMENT_DIR}/progress.log"

  # define client command:
  local -a networkQualityCommand=(
    ip netns exec client-net
    ./networkQuality
    --connect-to 10.237.0.3
    --insecure-skip-verify
    --relative-rpm
    --extended-stats
  )

  # we build the different parameter combis as a string array:
  build_parameter_array

  # loop over the environments (environment-name, capacities and delay in both directions)
  while IFS= read -r line || [ -n "${line}" ]; do    
    read -r envname dl_capacity ul_capacity dl_delay_from_inet ul_delay_to_inet <<< "${line}" # read the environment parameters
    mkdir "${MEASUREMENT_DIR}/${envname}"
    # loop over the test-parameters in the parameter combination array:  
    for ((index = 0; index < ${#PARAMETER_COMBINATIONS[@]}; index++)); do
      # combinations: the string that goes after the command
      # directory_name: the string that defines the dir-name
      # rpm_parameters: current combination
      combination="${PARAMETER_COMBINATIONS[index]}"
      directory_name="${PARAMETER_DIRECTORIES[index]}"
      read -r -a rpm_parameters <<< "$combination"
      TEST_DIR="${MEASUREMENT_DIR}/${envname}/${directory_name}"
      mkdir -p "$TEST_DIR"                    
      # we do 100 iterations
      for j in {1..100}; do
        echo "currently: ${envname}_${directory_name}_iteration${j}" > "${MEASUREMENT_DIR}/progress.log"
        
        iteration_dir="${TEST_DIR}/${j}"
        mkdir -p "${iteration_dir}"

        TEST_FILE="${iteration_dir}/test_output.log"
        PCAP_FILE="${iteration_dir}/traffic.pcap"
        KEYS_FILE="${iteration_dir}/test_keys.keys"
        SERVER_FILE="${iteration_dir}/server_output.log"

        touch ${TEST_FILE}
        cat /dev/null > ${TEST_FILE}  


        ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
        
        # start capturing packets
        # ip netns exec bottleneck-net tcpdump -s 100 -i br-client-inet -w "${PCAP_FILE}" 2> /tmp/tcpdump.log  &
        # TCPDUMP_PID=$!
        
        # start server and get pid for killing later
        ip netns exec server-net ./networkqualityd -create-cert --listen-addr 10.237.0.3 \
          >${SERVER_FILE} 2>&1 &
        SERVER_PID=$!
        
        # Wait until the server port is reachable
        ip netns exec client-net bash -c '
          for i in {1..300}; do
            timeout 0.2 bash -c "</dev/tcp/10.237.0.3/4043" >/dev/null 2>&1 && exit 0
            sleep 0.02
          done
          echo "Timed out waiting for 10.237.0.3:4043 from client-net" >&2
          exit 1
        ' || { kill "$SERVER_PID" 2>/dev/null || true; ./setup-shaping.sh DELETE; exit 1; }
        
        # log the set test parameters into output
        {
          echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}"

          for ((parameter_index = 0;
                parameter_index < ${#rpm_parameters[@]};
                parameter_index += 2)); do
            parameter_name="${rpm_parameters[parameter_index]#--rpm.}"
            parameter_value="${rpm_parameters[parameter_index + 1]}"
            echo "Testing parameter ${parameter_name}=${parameter_value}"
          done

          echo "iteration ${j}"
        } >> "$TEST_FILE"
        

        # start client and log it into output
        "${networkQualityCommand[@]}" \
          "${rpm_parameters[@]}" \
          >> "$TEST_FILE"

        # kill server and tcpdump and delete network
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
        # kill "$TCPDUMP_PID" 2>/dev/null || true
        # wait "$TCPDUMP_PID" 2>/dev/null || true
        ./setup-shaping.sh DELETE
        done 
    done
  done < rpmparameters/environments.txt
  endtime=$(date +%d-%m-%Y_%H-%M-%S)
  {
    echo "test done"
    echo "started at: ${starttime}"
    echo "ended at: ${endtime}"
  } > "${MEASUREMENT_DIR}/progress.log"
}


# iterParameters
iterParametersMulti
# touch "${MEASUREMENT_DIR}/output.csv"
# python3 create_csv.py "${MEASUREMENT_DIR}" # this will create a csv file with the output.txt
