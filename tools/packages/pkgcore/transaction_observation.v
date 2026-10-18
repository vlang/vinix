// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Activation internally borrows its configuration and prepared plan, including
// on a no-op. Public replies own all nested fields before those owners retire.
fn owned_transaction_state(state State) State {
	plan := owned_plan(Plan{requested: state.requested, packages: state.packages})
	return State{...state, architecture: state.architecture.clone(), requested: plan.requested, packages: plan.packages}
}
