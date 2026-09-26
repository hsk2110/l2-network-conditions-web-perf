import sys
from pathlib import Path
from collections import Counter
from scapy.all import PcapReader, TCP, IP, IPv6

def extract_all_mss_options(pcap_path):
    mss_counts = Counter()

    try:
        with PcapReader(str(pcap_path)) as pcap:
            for pkt in pcap:
                if not pkt.haslayer(TCP):
                    continue

                tcp = pkt[TCP]

                # Check TCP options for MSS on EVERY packet
                for option in tcp.options:
                    if option[0] == "MSS":
                        mss_value = option[1]
                        mss_counts[mss_value] += 1
                        break  # Found MSS for this packet, move to next packet

    except Exception as e:
        print(f"Error processing {pcap_path}: {e}")

    return mss_counts


if __name__ == "__main__":
    measurement_folder = Path(sys.argv[1])
    total_mss_counts = Counter()

    for file_path in measurement_folder.rglob("traffic.pcap"):
        if file_path.is_file():
            file_counts = extract_all_mss_options(file_path)
            total_mss_counts.update(file_counts)

    # Save or print the summary
    output_file = Path("mss_results.txt")
    with open(output_file, "w") as f:
        f.write("--- Summary of All Observed MSS Values in TCP Options ---\n")
        f.write(f"{'MSS Value':<15} | {'Packet Count'}\n")
        f.write("-" * 35 + "\n")
        for mss, count in total_mss_counts.most_common():
            f.write(f"{str(mss):<15} | {count}\n")

    print(f"Done! Results written to {output_file.resolve()}")