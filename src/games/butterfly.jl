export ButterflyGame,
    Butterfly,
    Pinecone, pinecone,
    observe,
    plan,
    generate_map, 
    spawn_agents,
    random_scene,
    render_image

"A game with butterflies =)"
struct ButterflyGame <: Game end

#################################################################################
# Game-specific elements
#################################################################################

@with_kw mutable struct Butterfly <: Agent
    position::SVector{2, Int64}
    energy::Float64 = 0.0
    policy::Policy = random_policy
end
position(agent::Butterfly) = agent.position
policy(agent::Butterfly) = agent.policy


struct Pinecone <: StaticElement end
const pinecone = Pinecone()


#################################################################################
# Game-specific agent implementation
#################################################################################

function observe(::ButterflyGame, agent::Player, agent_index::Int, state::GameState, kdtree::KDTree)::Observation
    # get all butterfly locations
    l_agents = length(state.agents)
    if l_agents == 1
        return NoObservation()
    end
    # get nearest two agents
    bounds = state.scene.bounds
    a, b = bounds
    r = max(a, b)
    idxs, dist = knn(kdtree, agent.position, 2, true)
    # returns the location of the nearest butterfly
    position = kdtree.data[idxs[2]]
    return PosObs(position)
end


function plan(::ButterflyGame, ::GreedyPolicy, agent::Player, agent_index::Int, obs::PosObs)
    # moves toward the nearest butterfly
    dy, dx = agent.position - obs.data
    direction = if abs(dx) > abs(dy)
        dx > 0 ? Left : Right
    else
        dy > 0 ? Up : Down
    end
    direction(agent_index)
end

#################################################################################
# Game definition
#################################################################################

function interaction_set(::ButterflyGame)
    set = [
        (Player => Obstacle) => Stepback,
        (Butterfly => Obstacle) => Stepback,
        (Butterfly => Player) => KilledBy,
        (Butterfly => Player) => ChangeScore,
        (Butterfly => Pinecone) => Retile{Ground},
        (Butterfly => Pinecone) => Clone,
    ]
end

function termination_set(::ButterflyGame)
    set = [
        TerminationRule(st -> isempty(findall(st.scene.items .== pinecone)), GameOver()), # no pinecones
        TerminationRule(st -> st.time > time, GameOver()), # Time out
        TerminationRule(st -> isempty(findall(x -> isa(x, Butterfly), st.agents)), GameWon()) # victory!
    ]
end

#################################################################################
# Scene initialization
#################################################################################

"""
    generate_map(game, setup)

Initialize state based on symbol map.
"""
function generate_map(::ButterflyGame, setup::String)::GameState
    h = count(==('\n'), setup) + 1
    w = 0
    for char in setup
        if char == '\n'
            break
        end
        w += 1
    end
    scene = GridScene((h, w))
    m = scene.items
    V = SVector{2, Int64}
    p_pos = Vector{V}()
    b_pos = Vector{V}()

    # StaticElements
    setup = replace(setup, r"\n" => "")
    setup = reshape(collect(setup), (w,h))
    setup = permutedims(setup, (2,1))

    for (index, char) in enumerate(setup)
        if char == 'w'
            m[index] = obstacle
        elseif char == '.'
            m[index] = ground
        elseif char == '0'
            m[index] = pinecone
        else
            ci = CartesianIndices(m)[index]
            if char == '1'
                push!(b_pos, ci)
            else
                push!(p_pos, ci)
            end
        end
    end

    # DynamicElements
    state = GameState(scene)
    for pos in p_pos
        p = Player(; position = pos)
        l = new_index(state)
        insert(state, l, p)
    end
    for pos in b_pos
        b = Butterfly(; position = pos)
        l = new_index(state)
        insert(state, l, b)
    end

    return(state)
end


"""
    spawn_agents(state, n_players)

Adds agents to state at random locations.
"""
function spawn_agents(state::GameState, n_players::Int64 = 1)
    # butterfly first (Poisson distribution)
    items = state.scene.items
    size = length(items)
    density = ceil(size/20)
    n_b = poisson(density)
    pot_pos = []
    @inbounds  for i in eachindex(items)
        if m[i] == ground
            push!(pot_pos, i)
        end
    end
    shuffle!(pot_pos)
    @inbounds for i = 1:n_b
        pos = pot_pos[i]
        b = Butterfly(pos)
        l = new_index(state)
        insert(state, l, b)
    end

    # player second
    for i = 1:n_players
        pos = pot_pos[n_b + i]
        p = Player(pos)
        l = new_index(state)
        insert(state, l, p)
    end
end

#################################################################################
# Scene rendering
#################################################################################

function random_scene(::ButterflyGame, bounds::Tuple, o_density::Float64, npinecones::Int64)::GridScene
    m = Matrix{StaticElement}(fill(ground, bounds)) 

    # obstacles first
    if o_density > 0
        @inbounds for i = eachindex(m)
            rand() < o_density && (m[i] = obstacle)
        end
    end
    # borders second
    m[1:end, 1] .= obstacle
    m[1:end, end] .= obstacle
    m[1, 1:end] .= obstacle
    m[end, 1:end] .= obstacle
    # pinecones last
    if npinecones > 0
        pine_map = findall(m .== ground)
        shuffle!(pine_map)
        @inbounds for i = 1:npinecones
            m[pine_map[i]] = pinecone
        end
    end

    scene = GridScene(bounds, m)
    return scene
end

color(::Ground) = gray_color
color(::Obstacle) = black_color
color(::Pinecone) = green_color
color(::Butterfly) = pink_color
color(::Player) = blue_color

function render_image(::ButterflyGame, state::GameState, path::String;
    img_res::Tuple{Int64, Int64} = (100,100))

    # StaticElements
    scene = state.scene
    bounds = scene.bounds
    items = scene.items
    img = fill(color(ground), bounds)
    img[findall(x -> x == obstacle, items)] .= color(obstacle)
    img[findall(x -> x == pinecone, items)] .= color(pinecone)

    # DynamicElements
    agents = state.agents
    for i in eachindex(agents)
    agent = agents[i]
    ci = CartesianIndex(agent.position)
    img[ci] = color(agent)
    end

    # save & open image
    img = repeat(img, inner = img_res)
    save(path, img)
    
end