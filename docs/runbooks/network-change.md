# Runbook: Network Change (VLAN / ACL / Routing)

## 1. Plan
1. Update `network/addressing/vlans.yaml` first. It is the source of truth.
2. Update the affected configs in `network/cisco/` and `network/fortigate/`.
3. Run the validator locally:
   ```bash
   python scripts/validate_network.py
   ```
4. Open a pull request. CI re-runs the validator, and a peer reviews the diff.

## 2. Pre-change (maintenance window)
- [ ] Back up running configs (`copy running-config tftp:` / FortiGate backup)
- [ ] Confirm HSRP state: `show standby brief` (SW1 active)
- [ ] Confirm OSPF neighbours: `show ip ospf neighbor`
- [ ] Confirm BGP to AWS: `show ip bgp summary` (both tunnels Established)

## 3. Apply
- Apply to the **standby** core (CORE-SW2) first, verify, then apply to CORE-SW1.
- For SVI changes, verify the HSRP VIP still answers from both switches.

## 4. Verify
- [ ] `ping` the VLAN gateway and a host in the new/changed VLAN
- [ ] `python scripts/network_perf.py --host <target>` passes latency/jitter/loss
- [ ] AWS route tables show the propagated prefix (if one was added)
- [ ] No new syslog errors / IPS blocks for legitimate traffic

## 5. Rollback
- `configure replace` from the backup, or re-apply the previous commit's config.
