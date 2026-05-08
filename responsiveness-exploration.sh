#!/bin/bash
#set -ex
if [[ ${EUID} -ne 0 ]]; then
	echo "$0 is not running as root. Try using sudo."
	exit 2
fi

# single dimensional iteration over pre-defined network environemnts
# the definitions are in environemnts.txt and will be iterated through accordingly
: '
iterEnvironments () {
  while IFS= read -r line || [ -n "${line}" ]; do    
    read -r envname dl_capacity ul_capacity dl_delay_from_inet ul_delay_to_inet <<< "${line}"
    echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> output.txt
    echo "Testing network environment ${envname} ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms"
    ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
    ip netns exec server-net ./networkqualityd -create-cert --public-name networkquality.example.com --listen-addr 10.237.0.3 &
    sleep 1
    ip netns exec client-net ./networkQuality --url https://networkquality.example.com:4043/.well-known/nq --insecure-skip-verify >> output.txt
    ./setup-shaping.sh DELETE
    printf "\n" >> output.txt
    sleep 1
  done < rpmparameters/environments.txt
  printf "finished with the environments\n\n" >> output.txt
}

# single dimensional iteration over responsiveness test parameters
# the definitions are in testparameters.txt and will be iterated through accordingly
iterTestParameters () {
  while IFS= read -r line || [ -n "$line" ]; do
    read -r test_parameter p_min p_max steps <<< "$line"    
    ./setup-shaping.sh CREATE 1000Mbit 1000Mbit 10ms 10ms
    sleep 1
    ip netns exec server-net ./networkqualityd -create-cert --public-name networkquality.example.com --listen-addr 10.237.0.3 &
    sleep 1
    i=$p_min
    # if parameter is a float
    if [[ "${test_parameter}" = "ptc" ]]; then
      while [ "$(bc <<< "$i <= $p_max")" == "1"  ]; do
        echo "Testing network environment FiberGlas 1000 1000 10 10" >> output.txt
        echo "Testing test parameter ${test_parameter} ${i}"
        echo "Testing test parameter ${test_parameter} ${i}" >> output.txt
        ip netns exec client-net ./networkQuality --url https://networkquality.example.com:4043/.well-known/nq --insecure-skip-verify  --"rpm.${test_parameter}" ${i} >> output.txt
        printf "\n" >> output.txt
        i=$(echo "$i + $steps" | bc -l)
      done
    # if parameter is a bool
    elif [[ "$test_parameter" = "parallel" ]]; then
      echo "Testing network environment FiberGlas 1000 1000 10 10" >> output.txt
      echo "Testing test parameter $test_parameter True"
      echo "Testing test parameter $test_parameter True" >> output.txt
      ip netns exec client-net ./networkQuality --url https://networkquality.example.com:4043/.well-known/nq --insecure-skip-verify  --"rpm.$test_parameter" >> output.txt
      printf "\n" >> output.txt 
    else
      while (( i <= p_max )); do
        echo "Testing network environment FiberGlas 1000 1000 10 10" >> output.txt
        echo "Testing test parameter $test_parameter $i"
        echo "Testing test parameter $test_parameter $i" >> output.txt
        ip netns exec client-net ./networkQuality --url https://networkquality.example.com:4043/.well-known/nq --insecure-skip-verify  --"rpm.$test_parameter" $i >> output.txt
        printf "\n" >> output.txt      
        ((i+=steps))
      done 
    fi
    
    ./setup-shaping.sh DELETE
    printf "\n" >> output.txt
    sleep 1
  done < rpmparameters/testparameters.txt
}
'

iterParameters () {
  # loop over the environments (environment-name, capacities and delay in both directions)
  while IFS= read -r line || [ -n "${line}" ]; do    
    read -r envname dl_capacity ul_capacity dl_delay_from_inet ul_delay_to_inet <<< "${line}"  
    # loop over the test-parameters (parameter-name, minimum and maximum value and iteration steps)  
    while IFS= read -r line || [ -n "$line" ]; do
      read -r test_parameter p_min p_max steps <<< "$line"
      i=$p_min
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
          for j in {1..100}; do            
            ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
            ip netns exec server-net ./networkqualityd -create-cert --public-name networkquality.example.com --listen-addr 10.237.0.3 \
              >server.log 2>&1 &
            server_pid=$!
            # Wait until the server port is reachable
            ip netns exec client-net bash -c '
              for i in {1..300}; do
                timeout 0.2 bash -c "</dev/tcp/10.237.0.3/4043" >/dev/null 2>&1 && exit 0
                sleep 0.02
              done
              echo "Timed out waiting for 10.237.0.3:4043 from client-net" >&2
              exit 1
            ' || { kill "$server_pid" 2>/dev/null || true; ./setup-shaping.sh DELETE; exit 1; }

            echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> output.txt
            echo "Testing network environment ${envname} ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms"
            echo "Testing test parameter ${test_parameter} ${i}"
            echo "Testing test parameter ${test_parameter} ${i}" >> output.txt
			echo "iteration ${j}"
			echo "iteration ${j}" >> output.txt

            ip netns exec client-net ./networkQuality \
              --url https://networkquality.example.com:4043/.well-known/nq \
              --insecure-skip-verify -relative-rpm -extended-stats --"rpm.${test_parameter}" ${i} >> output.txt
            printf "\n" >> output.txt
            kill "$server_pid" 2>/dev/null || true
            ./setup-shaping.sh DELETE         
          i=$(echo "$i + $steps" | bc -l)
          done
        done
      elif [[ "${test_parameter}" = "default" ]]; then
      # if we do a default iteration
      # 1. emulation start
      # 2. server start
      # 3. wait until server reachable
      # 4. client start
      # (4. Client's output gets logged)
      # 5. server and emulation shutdown
        for j in {1..100}; do            
          ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
          ip netns exec server-net ./networkqualityd -create-cert --public-name networkquality.example.com --listen-addr 10.237.0.3 \
            >server.log 2>&1 &
          server_pid=$!
          # Wait until the server port is reachable
          ip netns exec client-net bash -c '
            for i in {1..300}; do
              timeout 0.2 bash -c "</dev/tcp/10.237.0.3/4043" >/dev/null 2>&1 && exit 0
              sleep 0.02
            done
            echo "Timed out waiting for 10.237.0.3:4043 from client-net" >&2
            exit 1
          ' || { kill "$server_pid" 2>/dev/null || true; ./setup-shaping.sh DELETE; exit 1; }

          echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> output.txt
          echo "Testing network environment ${envname} ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms"
          echo "Testing default"
          echo "iteration ${j}"
		  echo "iteration ${j}" >> output.txt

          ip netns exec client-net ./networkQuality \
            --url https://networkquality.example.com:4043/.well-known/nq \
            --insecure-skip-verify -extended-stats -relative-rpm  >> output.txt
          printf "\n" >> output.txt
          kill "$server_pid" 2>/dev/null || true
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
          for j in {1..100}; do
            ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
            ip netns exec server-net ./networkqualityd -create-cert --public-name networkquality.example.com --listen-addr 10.237.0.3 \
              >server.log 2>&1 &
            server_pid=$!
            # Wait until the server port is reachable
            ip netns exec client-net bash -c '
              for i in {1..300}; do
                timeout 0.2 bash -c "</dev/tcp/10.237.0.3/4043" >/dev/null 2>&1 && exit 0
                sleep 0.02
              done
              echo "Timed out waiting for 10.237.0.3:4043 from client-net" >&2
              exit 1
            ' || { kill "$server_pid" 2>/dev/null || true; ./setup-shaping.sh DELETE; exit 1; }

            echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> output.txt
            echo "Testing network environment ${envname} ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms"
            echo "Testing test parameter ${test_parameter} ${i}"
            echo "Testing test parameter ${test_parameter} ${i}" >> output.txt
			echo "iteration ${j}"
			echo "iteration ${j}" >> output.txt
			
            ip netns exec client-net ./networkQuality \
              --url https://networkquality.example.com:4043/.well-known/nq \
              --insecure-skip-verify -extended-stats -relative-rpm --"rpm.${test_parameter}" ${i} >> output.txt
            printf "\n" >> output.txt
            kill "$server_pid" 2>/dev/null || true
            ./setup-shaping.sh DELETE
          done    
          ((i+=steps))
        done 
      fi     
      printf "\n" >> output.txt
    done < rpmparameters/testparameters.txt
    printf "\n" >> output.txt
  done < rpmparameters/environments.txt
}


if [ ! -f "output.txt" ]; then
    touch output.txt
fi
cat /dev/null > output.txt
iterParameters
mv output.txt outputfiles/
python3 create_csv.py
