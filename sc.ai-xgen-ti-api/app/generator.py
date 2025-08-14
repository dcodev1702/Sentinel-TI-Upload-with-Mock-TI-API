import os, json, uuid, random
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Any

def utcnow():
    return datetime.now(tz=timezone.utc)

def iso_z(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")

def stix_id(sdo: str) -> str:
    return f"{sdo}--{uuid.uuid4()}"

def rand_ip() -> str:
    return ".".join([str(random.randint(1, 254)),
                     str(random.randint(0, 255)),
                     str(random.randint(0, 255)),
                     str(random.randint(1, 253))])

def source_ti() -> str:
    return f"STEELCAGE.AI"

def rand_domain() -> str:
    prefixes = ['malware','c2','phish','exploit','dropper','payload','beacon','cobra','viper','shadow']
    middles = ['control','command','download','update','sync','data','info','stats','telemetry','metrics']
    tlds = ['.com','.net','.org','.info','.biz','.io','.tech','.xyz','.online','.site']
    return f"{random.choice(prefixes)}-{random.choice(middles)}{random.randint(100,999)}{random.choice(tlds)}"

def rand_url() -> str:
    domain = rand_domain()
    paths = ['/api/beacon','/update/check','/data/sync','/get/info','/ping','/cfg/get','/task/poll','/cmd/exec','/file/upload','/log/send']
    params = ['', '?id=', '?session=', '?key=', '?token=', '?user=']
    path = random.choice(paths)
    param = random.choice(params)
    if param:
        token = ''.join(random.choice('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789') for _ in range(8))
        param = f"{param}{token}"
    return f"https://{domain}{path}{param}"

def rand_md5() -> str:
    return uuid.uuid4().hex + uuid.uuid4().hex[:8]

def _md5_32(h: str) -> str:
    return (h.replace('-', '') + '0'*32)[:32]

def generate_payload(min_count: int = 10, max_count: int = 25) -> Dict[str, Any]:
    now = utcnow()
    valid_from = now - timedelta(days=random.randint(0, 10), hours=random.randint(0, 23))
    indicator_count = max(min_count, 1) if min_count == max_count else random.randint(min_count, max_count)

    malware_families = ['Emotet','TrickBot','Qbot','Cobalt Strike','Metasploit','Mimikatz','BloodHound','Empire','PsExec']
    threat_actors = ['APT28','APT29','Lazarus','FIN7','Carbanak','DarkHydrus','OilRig','MuddyWater','Turla']

    kill_chain_phases = [
        {"kill_chain_name": "lockheed-martin-cyber-kill-chain", "phase_name": "reconnaissance"},
        {"kill_chain_name": "lockheed-martin-cyber-kill-chain", "phase_name": "weaponization"},
        {"kill_chain_name": "lockheed-martin-cyber-kill-chain", "phase_name": "delivery"},
        {"kill_chain_name": "lockheed-martin-cyber-kill-chain", "phase_name": "exploitation"},
        {"kill_chain_name": "lockheed-martin-cyber-kill-chain", "phase_name": "installation"},
        {"kill_chain_name": "lockheed-martin-cyber-kill-chain", "phase_name": "command-and-control"},
        {"kill_chain_name": "lockheed-martin-cyber-kill-chain", "phase_name": "actions-on-objectives"},
    ]

    stixobjects: List[Dict[str, Any]] = []

    # Identities (first three actors)
    identities = []
    for actor in threat_actors[:3]:
        identity = {
            "type": "identity",
            "spec_version": "2.1",
            "id": stix_id("identity"),
            "created": iso_z(now),
            "modified": iso_z(now),
            "name": actor,
            "source": source_ti(),
            "description": f"Threat actor group {actor} - Known for sophisticated cyber operations",
            "identity_class": "group",
            "pattern": f"[identity:name = '{actor}']",
            "pattern_type": "stix",
            "valid_from": iso_z(valid_from),
        }
        stixobjects.append(identity)
        identities.append(identity)

    indicator_ids: List[str] = []
    for _ in range(indicator_count):
        itype = random.choice(['ipv4','domain','url','file-hash'])
        malware = random.choice(malware_families)
        actor = random.choice(threat_actors)
        confidence = random.randint(60, 100)
        indicator = {
            "type": "indicator",
            "spec_version": "2.1",
            "id": stix_id("indicator"),
            "source": source_ti(),
            "created": iso_z(now),
            "modified": iso_z(now),
            "valid_from": iso_z(valid_from),
            "pattern_type": "stix",
            "labels": ["malicious-activity"],
            "confidence": confidence,
        }
        if itype == 'ipv4':
            ip = rand_ip()
            indicator["pattern"] = f"[ipv4-addr:value = '{ip}']"
            indicator["name"] = f"Malicious IP - {malware} C2"
            indicator["description"] = f"IP address associated with {malware} activity attributed to threat actor: {actor}."
            indicator["kill_chain_phases"] = [ kill_chain_phases[5] ]
        elif itype == 'domain':
            dom = rand_domain()
            indicator["pattern"] = f"[domain-name:value = '{dom}']"
            indicator["name"] = f"Malicious Domain - {malware}"
            indicator["description"] = f"Domain used by {malware} infrastructure attributed to threat actor: {actor}."
            indicator["kill_chain_phases"] = [ kill_chain_phases[5], kill_chain_phases[4] ]
        elif itype == 'url':
            u = rand_url()
            indicator["pattern"] = f"[url:value = '{u}']"
            indicator["name"] = f"Malicious URL - {malware}"
            indicator["description"] = f"URL serving {malware} payload attributed to {actor} campaign."
            indicator["kill_chain_phases"] = [ kill_chain_phases[2], kill_chain_phases[3] ]
        else:
            h = _md5_32(rand_md5())
            indicator["pattern"] = f"[file:hashes.MD5 = '{h}']"
            indicator["name"] = f"Malicious File Hash - {malware}"
            indicator["description"] = f"MD5 hash of {malware} variant associated with {actor} operations."
            indicator["kill_chain_phases"] = [ kill_chain_phases[1], kill_chain_phases[2], kill_chain_phases[4] ]
        stixobjects.append(indicator)
        indicator_ids.append(indicator["id"])

    attack_patterns_src = [
        {"name": "Spearphishing Attachment", "description": "Adversaries send spearphishing emails with malicious attachments", "external_id": "T1566.001", "phases": [kill_chain_phases[2]]},
        {"name": "Command and Scripting Interpreter", "description": "Abuse of command and script interpreters", "external_id": "T1059", "phases": [kill_chain_phases[3], kill_chain_phases[4]]},
        {"name": "Remote System Discovery", "description": "Discovery of systems on the network", "external_id": "T1018", "phases": [kill_chain_phases[0], kill_chain_phases[6]]},
        {"name": "Credential Dumping", "description": "Dumping credentials to obtain account info", "external_id": "T1003", "phases": [kill_chain_phases[6]]},
    ]

    attack_pattern_ids: List[str] = []
    for ap in attack_patterns_src:
        ap_obj = {
            "type": "attack-pattern",
            "spec_version": "2.1",
            "id": stix_id("attack-pattern"),
            "created": iso_z(now),
            "modified": iso_z(now),
            "name": ap["name"],
            "source": source_ti(),
            "description": ap["description"],
            "pattern": f"[attack-pattern:name = '{ap['name']}']",
            "pattern_type": "stix",
            "valid_from": iso_z(valid_from),
            "kill_chain_phases": ap["phases"],
            "external_references": [{
                "source_name": "mitre-attack",
                "external_id": ap["external_id"],
                "url": f"https://attack.mitre.org/techniques/{ap['external_id']}/"
            }],
        }
        stixobjects.append(ap_obj)
        attack_pattern_ids.append(ap_obj["id"])

    for _ in range(min(5, len(indicator_ids))):
        source_id = random.choice(indicator_ids)
        target_id = random.choice(attack_pattern_ids)
        rel_type = random.choice(["indicates", "uses"])
        stixobjects.append({
            "type": "relationship",
            "spec_version": "2.1",
            "id": stix_id("relationship"),
            "created": iso_z(now),
            "modified": iso_z(now),
            "name": f"Relationship: {rel_type}",
            "source": source_ti(),
            "description": "Indicator relationship to attack pattern",
            "pattern": f"[relationship:type = '{rel_type}']",
            "pattern_type": "stix",
            "valid_from": iso_z(valid_from),
            "relationship_type": rel_type,
            "source_ref": source_id,
            "target_ref": target_id,
        })

    for _ in range(min(3, len(indicator_ids))):
        source_id = random.choice(indicator_ids)
        target = random.choice(identities)
        rel_type = "attributed-to"
        stixobjects.append({
            "type": "relationship",
            "spec_version": "2.1",
            "id": stix_id("relationship"),
            "created": iso_z(now),
            "modified": iso_z(now),
            "name": f"Relationship: {rel_type}",
            "source": source_ti(),
            "description": "Indicator attributed to threat actor group",
            "pattern": f"[relationship:type = '{rel_type}']",
            "pattern_type": "stix",
            "valid_from": iso_z(valid_from),
            "relationship_type": rel_type,
            "source_ref": source_id,
            "target_ref": target["id"],
        })

    payload = {
        "sourcesystem": "STEELCAGE.AI X-GEN TI PLATFORM",
        "stixobjects": stixobjects
    }
    return payload

def write_payload(output_dir: str, payload: Dict[str, Any]) -> str:
    os.makedirs(output_dir, exist_ok=True)
    ts = iso_z(utcnow()).replace(":", "").replace("-", "")
    out_path = os.path.join(output_dir, f"indicators_{ts}.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
    return out_path
