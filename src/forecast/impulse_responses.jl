"""
```
impulse_responses(m, system)

impulse_responses(system, horizon)
```

Compute impulse responses for a single draw.

### Inputs

- `m::AbstractModel`: model object
- `system::System{S}`: state-space system matrices
- `horizon::Int`: number of periods ahead to forecast
- `flip_shocks::Bool`: Whether to compute IRFs in response to a positive shock (by default the shock magnitude is a negative 1 std. shock)

where `S<:AbstractFloat`

### Outputs

- `states::Array{S, 3}`: matrix of size `nstates` x `horizon` x `nshocks` of
  state impulse response functions
- `obs::Array{S, 3}`: matrix of size `nobs` x `horizon` x `nshocks` of
  observable impulse response functions
- `pseudo::Array{S, 3}`: matrix of size `npseudo` x `horizon` x `nshocks` of
  pseudo-observable impulse response functions
"""
function impulse_responses(m::AbstractRepModel, system::System{S};
                           flip_shocks::Bool = false) where {S<:AbstractFloat}
    horizon = impulse_response_horizons(m)
    states, obs, pseudo = impulse_responses(system, horizon, flip_shocks = flip_shocks)
    return states, obs, pseudo
end

function impulse_responses_augmented(m::AbstractHetModel, system::System{S};
                                     flip_shocks::Bool = false,
                                     use_alternate_consumption = false) where {S<:AbstractFloat}
    @show "Impulse Responses: Het Model, Augmented"
    horizon = impulse_response_horizons(m)
    Qx = get_setting(m, :Qx)
    Qy = get_setting(m, :Qy)

    TTT_jump, TTT_state, eu, dF2_dRZ, dF2_dWH, dF2_dTT = klein(m)
    if eu == -1
        throw(KleinError())
    end

    TTT, RRR = klein_transition_matrices(m, TTT_state, TTT_jump)
    CCC      = zeros(n_model_states(m))
    C_eqn    = construct_consumption_eqn(m, TTT_jump, dF2_dRZ, dF2_dWH, dF2_dTT)
    TTT, RRR, CCC = augment_states(m, TTT, TTT_jump, RRR, CCC, C_eqn)

    measurement_equation = measurement(m, TTT, RRR, CCC, C_eqn)
    transition_equation = Transition(TTT, RRR, CCC)
    system = System(transition_equation, measurement_equation)

    states, obs, pseudo = impulse_responses(system, horizon, flip_shocks = flip_shocks)

    state_indices_orig = stack_indices(m.endogenous_states_original, get_setting(m, :states))
    jump_indices_orig  = stack_indices(m.endogenous_states_original, get_setting(m, :jumps))

    # In this case, the length of state_indices and jump_indices seems to give the number of
    # UNNORMALIZED states/jumps however I'm not sure if this will always be the case/if this is
    # really what we want saved into these settings...so might need to modify in future.
    states_unnormalized = Array{Float64}(undef, length(state_indices_orig),
                                         horizon, size(states, 3))
    jumps_unnormalized = Array{Float64}(undef, length(jump_indices_orig), horizon, size(states, 3))

    model_states_unnormalized = Array{Float64}(undef, length(state_indices_orig) +
                                               length(jump_indices_orig) +
                                               length(m.endogenous_states_augmented), horizon, size(states, 3))
    for i in 1:size(states, 3)
        state_inds = 1:n_backward_looking_states(m)
        states_unnormalized[:, :, i] = Matrix(Qx')*states[state_inds, :, i]
        jump_inds = n_backward_looking_states(m)+1:n_backward_looking_states(m) + n_jumps(m)
        jumps_unnormalized[:, :, i] = Matrix(Qy')*states[jump_inds, :, i]

        augmented_states = states[n_backward_looking_states(m) + n_jumps(m) + 1 : end, :, i]
        model_states_unnormalized[:, :, i] = vcat(states_unnormalized[:, :, i],
                                                  jumps_unnormalized[:, :, i],
                                                  augmented_states)
    end

    if use_alternate_consumption
        print("using alternate consumption inside augmented function")

        endo = m.endogenous_states_original
        @show endo
        c_implied = (m[:ystar]/m[:g]) - m[:xstar]
        IRFC_implied = m[:ystar]/(c_implied*m[:g])*(model_states_unnormalized[endo[:y′_t], :, :]  - model_states_unnormalized[endo[:g′_t], :, :]) - (m[:xstar]/c_implied)*model_states_unnormalized[endo[:I′_t], :, :]
        model_states_unnormalized[1229, :, :] = IRFC_implied

        z_consumption = model_states_unnormalized[endo[:z′_t], :, :]
        g_lag = cat(0, model_states_unnormalized[endo[:g′_t], :, :], dims = 2)[:, 1:40, :]
        IRFC_implied_lag = m[:ystar]/(c_implied*m[:g])*(model_states_unnormalized[endo[:y′_t1], :, :]  - g_lag) - (m[:xstar]/c_implied)*model_states_unnormalized[endo[:I′_t1], :, :] #cat(0, IRFC_implied, dims = 2)[:, 1:40, :]
        IRF_observable_implied = IRFC_implied - IRFC_implied_lag .+ z_consumption
        obs[m.observables[:obs_consumption], :, :] = IRF_observable_implied
    end

    return model_states_unnormalized, obs, pseudo
end

function impulse_responses(m::AbstractHetModel, system::System{S};
                           flip_shocks::Bool = false,
                           use_augmented_states::Bool = true,
                           use_alternate_consumption::Bool = false) where {S<:AbstractFloat}
    if use_augmented_states
        @show "Using augmented function"
        return impulse_responses_augmented(m, system, flip_shocks = flip_shocks,
                                           use_alternate_consumption = use_alternate_consumption)
    end


    @show "Impulse Responses: Het Model"
    horizon = impulse_response_horizons(m)
    Qx = get_setting(m, :Qx)
    Qy = get_setting(m, :Qy)

    states, obs, pseudo = impulse_responses(system, horizon, flip_shocks = flip_shocks)

    state_indices_orig = stack_indices(m.endogenous_states_original, get_setting(m, :states))
    jump_indices_orig  = stack_indices(m.endogenous_states_original, get_setting(m, :jumps))

    # In this case, the length of state_indices and jump_indices seems to give the number of
    # UNNORMALIZED states/jumps however I'm not sure if this will always be the case/if this is
    # really what we want saved into these settings...so might need to modify in future.
    states_unnormalized = Array{Float64}(undef, length(state_indices_orig),
                                         horizon, size(states, 3))
    jumps_unnormalized = Array{Float64}(undef, length(jump_indices_orig), horizon, size(states, 3))
    model_states_unnormalized = Array{Float64}(undef, length(state_indices_orig) +
                                               length(jump_indices_orig), horizon, size(states, 3))
    for i in 1:size(states, 3)
        state_inds = 1:n_backward_looking_states(m)
        states_unnormalized[:, :, i] = Matrix(Qx')*states[state_inds, :, i]
        jump_inds = n_backward_looking_states(m)+1:n_backward_looking_states(m) + n_jumps(m)
        jumps_unnormalized[:, :, i] = Matrix(Qy')*states[jump_inds, :, i]

        model_states_unnormalized[:, :, i] = vcat(states_unnormalized[:, :, i],
                                                  jumps_unnormalized[:, :, i])
    end

    if use_alternate_consumption
        endo_orig = m.endogenous_states_original
        c_implied = (m[:ystar]/m[:g]) - m[:xstar]
        IRFC_implied = m[:ystar]/(c_implied*m[:g])*(model_states_unnormalized[endo_orig[:y′_t], :, :]  - model_states_unnormalized[endo_orig[:g′_t], :, :]) - (m[:xstar]/c_implied)*model_states_unnormalized[endo_orig[:I′_t], :, :]
        model_states_unnormalized = vcat(model_states_unnormalized, IRFC_implied)

        z_consumption = model_states_unnormalized[m.endogenous_states_original[:z′_t], :, :]
        IRFC_implied_lag = cat(0, IRFC_implied, dims = 2)[:, 1:40, :]
        IRF_observable_implied = IRFC_implied - IRFC_implied_lag .+ z_consumption
        obs[m.observables[:obs_consumption], :, :] = IRF_observable_implied
    end

    return model_states_unnormalized, obs, pseudo
end

function impulse_responses(system::System{S}, horizon::Int;
                           flip_shocks::Bool = false) where {S<:AbstractFloat}
    # Setup
    nshocks      = size(system[:RRR], 2)
    nstates      = size(system[:TTT], 1)
    nobs         = size(system[:ZZ], 1)
    npseudo      = size(system[:ZZ_pseudo], 1)

    states = zeros(S, nstates, horizon, nshocks)
    obs    = zeros(S, nobs,    horizon, nshocks)
    pseudo = zeros(S, npseudo, horizon, nshocks)

    # Set constant system matrices to 0
    system = zero_system_constants(system)

    s_0 = zeros(S, nstates)

    for i = 1:nshocks
        # Isolate single shock
        shocks = zeros(S, nshocks, horizon)
        if flip_shocks
            shocks[i, 1] = sqrt(system[:QQ][i, i]) # a positive 1 s.d. shock
        else
            shocks[i, 1] = -sqrt(system[:QQ][i, i]) # a negative 1 s.d. shock
        end
        # Iterate state space forward
        states[:, :, i], obs[:, :, i], pseudo[:, :, i], _ = forecast(system, s_0, shocks)
    end

    return states, obs, pseudo
end

# Method for specifying the subset of shocks, and the size of each shock
function impulse_responses(m::AbstractModel, system::System{S},
                           horizon::Int, shock_names::Vector{Symbol},
                           shock_values::Vector{Float64}) where S<:AbstractFloat

    # Must provide a name and value for each shock
    @assert length(shock_names) == length(shock_values)

    # Setup
    exo          = m.exogenous_shocks
    nshocks      = size(system[:RRR], 2)
    nstates      = size(system[:TTT], 1)
    nobs         = size(system[:ZZ], 1)
    npseudo      = size(system[:ZZ_pseudo], 1)

    states = zeros(S, nstates, horizon, nshocks)
    obs    = zeros(S, nobs,    horizon, nshocks)
    pseudo = zeros(S, npseudo, horizon, nshocks)

    # Set constant system matrices to 0
    system = zero_system_constants(system)

    s_0 = zeros(S, nstates)

    for (i, shock) in enumerate(shock_names)
        # Isolate single shock
        shocks = zeros(S, nshocks, horizon)
        shocks[exo[shock], 1] = shock_values[i]

        # Iterate state space forward
        states[:, :, exo[shock]], obs[:, :, exo[shock]], pseudo[:, :, exo[shock]], _ = forecast(system, s_0, shocks)
    end

    return states, obs, pseudo
end

# Method for picking a specific shock and the size of the desired shift in the state or
# observed variable using that shock. (Omitting the feature to do pseudo-observables
# now, for simplicity)
function impulse_responses(m::AbstractModel, system::System{S},
                           horizon::Int, shock_name::Symbol,
                           var_name::Symbol, var_value::Float64) where S<:AbstractFloat


    # Setup
    var_names, var_class =
    if var_name in keys(m.endogenous_states)
        m.endogenous_states, :states
    elseif var_name in keys(m.observables)
        m.observables, :obs
    end
    exo          = m.exogenous_shocks
    nshocks      = size(system[:RRR], 2)
    nstates      = size(system[:TTT], 1)
    nobs         = size(system[:ZZ], 1)
    npseudo      = size(system[:ZZ_pseudo], 1)

    states = zeros(S, nstates, horizon, nshocks)
    obs    = zeros(S, nobs,    horizon, nshocks)
    pseudo = zeros(S, npseudo, horizon, nshocks)

    # Set constant system matrices to 0
    system = zero_system_constants(system)

    s_0 = zeros(S, nstates)

    # Isolate single shock
    shocks = zeros(S, nshocks, horizon)
    if var_class == :states
        shocks[exo[shock_name], 1] = obtain_shock_from_desired_state_value(var_value,
                                                                      var_names[var_name],
                                                                      exo[shock_name],
                                                                      system[:RRR])
    else # == :obs
        shocks[exo[shock_name], 1] = obtain_shock_from_desired_obs_value(var_value,
                                                                    var_names[var_name],
                                                                    exo[shock_name],
                                                                    system[:ZZ],
                                                                    system[:RRR])
    end

    # Iterate state space forward
    states[:, :, exo[shock_name]], obs[:, :, exo[shock_name]], pseudo[:, :, exo[shock_name]], _ = forecast(system, s_0, shocks)

    return states, obs, pseudo
end

# Given a desired value, x, for some state s^i_1, back out the necessary value of
# ϵ^j_1 needed s.t. s^i_1 = x.
# E.g. if I want the impulse response of output (s^i_1) to be 50 basis points
# based on a shock to productivity (ϵ^j_1), how large does that shock
# to productivity need to be?
# The answer is ϵ^j_1 = x/R_{i,j}
function obtain_shock_from_desired_state_value(state_value::Float64, state_ind::Int,
                                               shock_ind::Int, RRR::Matrix{Float64})
    return state_value/RRR[state_ind, shock_ind]
end

# Similar principle to the function for states
# The answer is ϵ^j_1 = x/{Σ_{k=1}^n Z_{i, k} R_{k, j}},
# where n is the total number of states, i is the index of the observable of interest
# y^i_1, and j is the index of the shock of interest, ϵ^j_1
function obtain_shock_from_desired_obs_value(obs_value::Float64, obs_ind::Int,
                                             shock_ind::Int, ZZ::Matrix{Float64},
                                             RRR::Matrix{Float64})
    return obs_value/dot(ZZ[obs_ind, :], RRR[:, shock_ind])
end
