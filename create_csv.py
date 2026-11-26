import csv
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# index        0
fieldnames = ['exp_parameters']
# index                    1              2              3           4
environment_parameters = ['dl_capacity', 'ul_capacity', 'dl_delay', 'ul_delay']
# index            5     6      7      8      9      10     11   12     13     14         15
rpm_parameters = ['id', 'inc', 'inp', 'mad', 'mnp', 'mps', 'p', 'ptc', 'sdt', 'timeout', 'tmp']

# index            16                       17                          18               19                20                 21                 22                 23                    24            25            26          27
dl_test_output = ['dl_stable_throughput',  'dl_stable_responsiveness', 'dl_throughput', 'dl_connections', 'dl_max_path_mtu', 'dl_max_send_mss', 'dl_max_recv_mss', 'dl_retransmissions', 'dl_reorder', 'dl_avg_rtt', 'dl_rpm_p', 'dl_rpm_trimmed']
# index            28                       29                          30               31                32                 33                 34                 35                    36            37            38          39
ul_test_output = ['ul_stable_throughput',  'ul_stable_responsiveness', 'ul_throughput', 'ul_connections', 'ul_max_path_mtu', 'ul_max_send_mss', 'ul_max_recv_mss', 'ul_retransmissions', 'ul_reorder', 'ul_avg_rtt', 'ul_rpm_p', 'ul_rpm_trimmed']
# index               40              41
final_test_output = ['final_rpm_p', 'final_rpm_trimmed']
# index                  42               43                     44            45                  46             47
relative_test_output = ['ub_base_rpm_p', 'ub_base_rpm_trimmed', 'base_rpm_p', 'base_rpm_trimmed', 'wc_effect_p', 'wc_effect_trimmed']
# index  48
misc = ['iteration']

fieldnames = fieldnames + environment_parameters + rpm_parameters + dl_test_output + ul_test_output + final_test_output + relative_test_output + misc


def initData(data):
    for i in range(0, 5):
        data[fieldnames[i]] = ''
    data[fieldnames[5]] = '1'       #id
    data[fieldnames[6]] = '1'       #inc
    data[fieldnames[7]] = '1'       #inp
    data[fieldnames[8]] = '4'       #mad
    data[fieldnames[9]] = '16'      #mnp
    data[fieldnames[10]] = '100'    #mps
    data[fieldnames[11]] = '90'     #p
    data[fieldnames[12]] = '0.05'   #ptc
    data[fieldnames[13]] = '5'      #sdt
    data[fieldnames[14]] = '20'     #timeout
    data[fieldnames[15]] = '5'      #tmp
    data[fieldnames[16]] = 'True'   #dl_stable_throughput
    data[fieldnames[17]] = 'True'   #dl_stable_responsiveness
    data[fieldnames[28]] = 'True'   #ul_stable_throughput
    data[fieldnames[29]] = 'True'   #ul_stable_responsiveness
    data[fieldnames[48]] = ''       #iteration


def parseParameterLine(split_line):
    """Return (key, value) pairs of a 'Testing ... parameter' line.

    multi-dim: 'Testing parameter inc=4'      -> [('inc', '4')]
    1-D:       'Testing test parameter mps 40' -> [('mps', '40')]
    """
    if any("=" in tok for tok in split_line):
        return [tuple(tok.split("=", 1)) for tok in split_line[2:] if "=" in tok]
    return [(split_line[3], split_line[4])]


def setParameter(data, key, value, filename):
    if key not in rpm_parameters:
        print(f"WARNING: unknown parameter '{key}' in {filename}, skipped")
        return False
    data[key] = value
    data[fieldnames[0]] += " " + key + "=" + value
    return True


def parseParameterFolder(name):
    """'inc=1__mnp=16__mps=100' -> {'inc': '1', 'mnp': '16', 'mps': '100'}; {} if not that pattern."""
    if "=" not in name:
        return {}
    params = {}
    for part in name.split("__"):
        if "=" in part:
            key, value = part.split("=", 1)
            params[key] = value
    return params


def checkPath(data, filename, log_params):
    """Cross-check / fill data from the folder layout
    measurement_x/<Network>/<k=v__k=v...>/<run>/test_output.log"""
    try:
        parts = Path(filename).relative_to(measurement_folder).parts
    except ValueError:
        return
    if len(parts) < 4:
        return

    network, param_folder, run = parts[-4], parts[-3], parts[-2]

    if run.isdigit() and not data[fieldnames[48]]:
        data[fieldnames[48]] = run

    folder_params = parseParameterFolder(param_folder)
    if folder_params:
        for key, value in folder_params.items():
            if key in log_params:
                if log_params[key] != value:
                    print(f"WARNING: {filename}: folder says {key}={value}, log says {key}={log_params[key]}")
            else:
                setParameter(data, key, value, filename)

        env_name = data[fieldnames[0]].split(" ", 1)[0]
        if env_name and env_name != network:
            print(f"WARNING: {filename}: folder network '{network}' != log network '{env_name}'")


def parseFile(filename):
    data = {}
    initData(data)
    download = True
    readResults = False
    log_params = {}
    f = fieldnames  # local alias for slightly faster lookups

    with open(filename, "r") as file:
        for raw_line in file:
            line = raw_line.strip()
            if not line:
                continue

            if not readResults:
                if line.startswith("Testing"):
                    split_line = line.split()
                    if "environment" in line:
                        for i in range(0, 5):
                            data[f[i]] = split_line[i + 3]
                    else:
                        for key, value in parseParameterLine(split_line):
                            if setParameter(data, key, value, filename):
                                log_params[key] = value
                elif line.startswith("Unbounded Baseline RPM:"):
                    split_line = line.split()
                    if "Trimmed" in line:
                        data[f[43]] = split_line[3]
                    else:
                        data[f[42]] = split_line[3]
                elif line.startswith("Baseline RPM:"):
                    split_line = line.split()
                    if "Trimmed" in line:
                        data[f[45]] = split_line[2]
                    else:
                        data[f[44]] = split_line[2]
                elif line.startswith("iteration"):
                    split_line = line.split()
                    data[f[48]] = split_line[1]
                elif line == "Results:":
                    readResults = True
            else:
                if line.startswith("Download"):
                    download = True
                elif line.startswith("Upload"):
                    download = False
                elif line.startswith("Note"):
                    if "responsiveness" in line:
                        data[f[17] if download else f[29]] = "False"
                    if "throughput" in line:
                        data[f[16] if download else f[28]] = "False"
                elif line.startswith("Throughput"):
                    split_line = line.split()
                    if download:
                        data[f[18]] = split_line[1]
                        data[f[19]] = split_line[6]
                    else:
                        data[f[30]] = split_line[1]
                        data[f[31]] = split_line[6]
                elif "MTU" in line:
                    split_line = line.split()
                    data[f[20] if download else f[32]] = split_line[3]
                elif "Send" in line:
                    split_line = line.split()
                    data[f[21] if download else f[33]] = split_line[3]
                elif "Recv" in line:
                    split_line = line.split()
                    data[f[22] if download else f[34]] = split_line[3]
                elif "Retransmissions" in line:
                    split_line = line.split()
                    data[f[23] if download else f[35]] = split_line[2]
                elif "Reorderings" in line:
                    split_line = line.split()
                    data[f[24] if download else f[36]] = split_line[2]
                elif line.startswith("Average RTT:"):
                    split_line = line.split()
                    data[f[25] if download else f[37]] = split_line[2]
                elif line.startswith("RPM"):
                    split_line = line.split()
                    if "Trimmed" in line:
                        data[f[27] if download else f[39]] = split_line[1]
                    else:
                        data[f[26] if download else f[38]] = split_line[1]
                elif line.startswith("Final"):
                    split_line = line.split()
                    if "Trimmed" in line:
                        data[f[41]] = split_line[2]
                    else:
                        data[f[40]] = split_line[2]
                elif line.startswith("Working"):
                    split_line = line.split()
                    if "Trimmed" in line:
                        data[f[47]] = split_line[5][:-1]
                        readResults = False
                    else:
                        data[f[46]] = split_line[5][:-1]

    checkPath(data, filename, log_params)
    return data


def sortKey(data):
    it = data[fieldnames[48]]
    return (data[fieldnames[0]], int(it) if it.isdigit() else -1)


# if you work on the server you have to edit the path!!!! (dont forget like last time!)
measurement_folder = Path(sys.argv[1])
csvfile = measurement_folder / "output.csv"

files = [p for p in measurement_folder.rglob("test_output.log") if p.is_file()]

with ThreadPoolExecutor(max_workers=min(32, (os.cpu_count() or 1) + 4)) as ex:
    datalist = list(ex.map(parseFile, files))

datalist.sort(key=sortKey)

# write the datalist into the csv file
with open(csvfile, "w", newline="") as f_out:
    writer = csv.DictWriter(f_out, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(datalist)

print(f"created csv with {len(datalist)} rows: {csvfile}")
