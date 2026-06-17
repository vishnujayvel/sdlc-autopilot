#!/usr/bin/env bats
# tests/integration/source-chain.bats — Verify the full production source chain loads without gaps
# Ensures that sourcing the libs in the same order as pdlc-outer-loop.sh (and hooks)
# makes all expected declare -f guarded functions available.

load ../helpers/common-setup

@test "full source chain makes core functions available" {
  # Simulate the exact source order used by outer-loop + common hooks
  source "${HOOKS_DIR}/lib/pdlc-state.sh"
  source "${HOOKS_DIR}/lib/pdlc-lifecycle.sh"
  source "${HOOKS_DIR}/lib/pdlc-director.sh"
  source "${HOOKS_DIR}/lib/pdlc-critic.sh"
  source "${HOOKS_DIR}/lib/pdlc-session.sh"
  source "${HOOKS_DIR}/lib/pdlc-freshness.sh"
  # pdlc-test-strategy may be optional in some paths; include if present
  if [[ -f "${HOOKS_DIR}/lib/pdlc-test-strategy.sh" ]]; then
    source "${HOOKS_DIR}/lib/pdlc-test-strategy.sh"
  fi

  # Core state
  declare -f pdlc_get_field >/dev/null
  declare -f pdlc_set_field >/dev/null
  declare -f pdlc_count_tasks >/dev/null
  declare -f pdlc_write_handoff >/dev/null

  # Lifecycle
  declare -f pdlc_lifecycle_infer >/dev/null
  declare -f pdlc_lifecycle_transition >/dev/null

  # Director + critic (the key wiring that was previously missing in outer-loop)
  declare -f pdlc_director_decide >/dev/null
  declare -f pdlc_director_evaluate_critics >/dev/null
  declare -f pdlc_critic_advocate >/dev/null
  declare -f pdlc_critic_skeptic >/dev/null
  declare -f pdlc_critic_consensus >/dev/null
  declare -f pdlc_critic_report >/dev/null

  # Session / freshness
  declare -f pdlc_session_save >/dev/null
  declare -f pdlc_session_restore >/dev/null
  declare -f pdlc_freshness_report >/dev/null

  # At least one cross-lib dependency function from xref/placeholder (pulled by critic)
  # These are soft; only assert if the sourcing pulled them (they are sourced on-demand inside critic)
  # The important thing is the top-level guarded functions above are now declared.
}

@test "pdlc_director_evaluate_critics is reachable after critic source (structured path)" {
  source "${HOOKS_DIR}/lib/pdlc-state.sh"
  source "${HOOKS_DIR}/lib/pdlc-critic.sh"
  source "${HOOKS_DIR}/lib/pdlc-director.sh"

  # Should have the structured consensus path (not only the simple fallback)
  declare -f pdlc_critic_consensus >/dev/null

  # Call with a PASS/PASS case (should go through consensus and return accept)
  result=$(pdlc_director_evaluate_critics 1 0)
  [[ "$result" == "accept" || "$result" == "accept-with-caveats" ]]
}