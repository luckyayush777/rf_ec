/** Service order is read from the model's `requires` metadata. Only exceptions live here. */
export type ServicePart = {
  id: string;
  kind: 'assembly' | 'fastener' | 'connector';
  parent?: string;
  requires: readonly string[];
};

export type ServiceAction = {
  kind: 'remove' | 'refit' | 'pickup' | 'disconnect' | 'connect';
  part: string;
};

export type ServiceFacts = {
  isRemoved: (part: string) => boolean;
  isConnected: (part: string) => boolean;
  equippedTool: 'screwdriver' | 'blower' | 'scraper' | null;
};

export type ServiceDecision =
  | { allowed: true; missing: readonly string[]; reason: '' }
  | { allowed: false; missing: readonly string[]; reason: string };

// Cooler fasteners must wait for the cable. The assembly's own requirements
// still come from the model, so adding another cooler screw needs no new guard.
export const gpuServiceExceptions = [
  { assembly: 'cooler-assembly', fastenersRequire: ['fan-plug'] },
] as const;

type Exception = { assembly: string; fastenersRequire: readonly string[] };

export function createServiceRules(parts: readonly ServicePart[], exceptions: readonly Exception[] = []) {
  const byId = new Map(parts.map(part => [part.id, part]));
  if (byId.size !== parts.length) throw new Error('Duplicate service part ID.');
  const removal = new Map(parts.map(part => [part.id, [...part.requires]]));
  for (const exception of exceptions) {
    const assembly = byId.get(exception.assembly);
    if (!assembly || assembly.kind !== 'assembly') throw new Error(`Missing service assembly: ${exception.assembly}`);
    const fasteners = assembly.requires.filter(id => byId.get(id)?.kind === 'fastener');
    if (!fasteners.length) throw new Error(`No fasteners declared for ${exception.assembly}.`);
    for (const id of fasteners) {
      removal.get(id)!.push(...exception.fastenersRequire);
    }
  }
  for (const [id, requirements] of removal) {
    for (const required of requirements) {
      if (!byId.has(required)) throw new Error(`Unknown service requirement ${required} for ${id}.`);
    }
  }
  const visiting = new Set<string>();
  const visited = new Set<string>();
  function visit(id: string) {
    if (visiting.has(id)) throw new Error(`Circular service requirements involving ${id}.`);
    if (visited.has(id)) return;
    visiting.add(id);
    for (const requirement of removal.get(id)!) visit(requirement);
    visiting.delete(id); visited.add(id);
  }
  for (const id of byId.keys()) visit(id);

  const label = (id: string) => id.replace(/-assembly$/, '').replace(/-screw-\d+$/, '').replace(/-/g, ' ');
  const connectorLabel = (id: string) => id === 'fan-plug' ? 'fan cable' : label(id);
  const joined = (ids: readonly string[]) => ids.map(label).join(' and ');
  const requiresPart = (id: string) => parts.filter(part => part.kind === 'assembly' && part.requires.includes(id));
  const installed = (id: string, facts: ServiceFacts) => byId.get(id)?.kind === 'connector'
    ? facts.isConnected(id) : !facts.isRemoved(id);
  const removed = (id: string, facts: ServiceFacts) => byId.get(id)?.kind === 'connector'
    ? !facts.isConnected(id) : facts.isRemoved(id);
  const allow: ServiceDecision = { allowed: true, missing: [], reason: '' };
  const deny = (reason: string, missing: readonly string[] = []): ServiceDecision => ({ allowed: false, missing, reason });

  function check(action: ServiceAction, facts: ServiceFacts): ServiceDecision {
    const part = byId.get(action.part);
    if (!part) throw new Error(`Unknown service part: ${action.part}`);
    if (part.kind === 'fastener' && action.kind !== 'remove' && action.kind !== 'refit') throw new Error(`Invalid fastener action: ${action.kind}`);
    if (part.kind === 'assembly' && !['remove', 'refit', 'pickup'].includes(action.kind)) throw new Error(`Invalid assembly action: ${action.kind}`);
    if (part.kind === 'connector' && action.kind !== 'connect' && action.kind !== 'disconnect') throw new Error(`Invalid connector action: ${action.kind}`);

    if (part.kind === 'fastener' && facts.equippedTool !== 'screwdriver') return deny('Pick up the screwdriver to remove or refit a screw.');
    if (part.kind !== 'fastener' && facts.equippedTool) {
      const task = part.kind === 'connector' ? `handling the ${connectorLabel(part.id)}`
        : action.kind === 'refit' ? 'refitting the assembly' : 'picking up the assembly';
      return deny(`Set the ${facts.equippedTool} down before ${task}.`);
    }

    if (action.kind === 'remove') {
      const missing = [...new Set(removal.get(part.id)!.filter(id => !removed(id, facts)))];
      if (!missing.length) return allow;
      const connector = missing.find(id => byId.get(id)?.kind === 'connector');
      if (connector) {
        return deny(part.kind === 'fastener'
          ? `Unplug the ${connectorLabel(connector)} before removing the ${label(part.id)} screws.`
          : `Unplug the ${connectorLabel(connector)} first.`, missing);
      }
      const screws = missing.filter(id => byId.get(id)?.kind === 'fastener');
      if (part.kind === 'assembly' && screws.length === missing.length) {
        return deny(`Remove the ${screws.length} remaining ${label(part.id)} screw${screws.length === 1 ? '' : 's'} with the screwdriver first.`, missing);
      }
      return deny(`Remove ${joined(missing)} before removing ${label(part.id)}.`, missing);
    }

    if (action.kind === 'refit') {
      const required = part.kind === 'assembly'
        ? [part.parent].filter((id): id is string => byId.get(id ?? '')?.kind === 'assembly')
        : requiresPart(part.id).map(assembly => assembly.id);
      const missing = required.filter(id => !installed(id, facts));
      if (!missing.length) return allow;
      return deny(part.kind === 'fastener'
        ? `Refit ${joined(missing)} before tightening its screws.`
        : `Refit ${joined(missing)} before refitting ${label(part.id)}.`, missing);
    }

    if (action.kind === 'connect') {
      const missing = requiresPart(part.id).map(assembly => assembly.id).filter(id => !installed(id, facts));
      if (missing.length) return deny(`Refit ${joined(missing)} before reconnecting the ${connectorLabel(part.id)}.`, missing);
    }
    return allow;
  }

  return { check };
}
