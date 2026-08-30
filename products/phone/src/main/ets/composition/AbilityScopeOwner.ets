/**
 * Tracks the UIAbility instance that owns the product composition graph.
 *
 * This class deliberately knows nothing about AbilityKit.  AppContainer keeps
 * the concrete UIAbilityContext at the product boundary and uses object
 * identity only to prevent a late teardown from an old Ability releasing the
 * graph already rebuilt for a newer Ability.
 */
export class AbilityScopeOwner {
  private owner: Object | undefined = undefined;

  hasOwner(): boolean {
    return this.owner !== undefined;
  }

  owns(candidate: Object): boolean {
    return this.owner === candidate;
  }

  /** Returns true when the owner changed. */
  attach(candidate: Object): boolean {
    if (this.owner === candidate) {
      return false;
    }
    this.owner = candidate;
    return true;
  }

  /** A stale Ability is never allowed to release the current owner. */
  release(candidate: Object): boolean {
    if (this.owner !== candidate) {
      return false;
    }
    this.owner = undefined;
    return true;
  }
}
