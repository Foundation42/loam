**MATRYOSHKA**

Sparse Field Dynamics Library

Architecture & Interface Specification

Draft 0.1 \| September 2026

> *A renderer-neutral sparse field substrate for evolving worlds: continuous spatial state, local operators, history, morphogenesis, and efficient path-traced sampling.*

| Status              | Exploratory architecture / implementation specification          |
|---------------------|------------------------------------------------------------------|
| Primary consumer    | Matryoshka path tracer                                           |
| Core representation | Sparse heterogeneous hierarchical field                          |
| Design principle    | Simulation writes/evolves fields; renderers query/integrate them |

# 1. Purpose

This document specifies a standalone Sparse Field Dynamics library intended to sit beneath Matryoshka and other consumers. The library represents spatially sparse, continuously sampleable fields whose state can evolve through local operators. Growth is one use case rather than the defining abstraction.

The central architectural boundary is deliberately simple: the simulation owns field state and evolution; Matryoshka owns ray generation, traversal policy, sampling strategy, light transport, temporal accumulation, and final rendering.

# 2. Design goals

- Represent material and non-material phenomena using the same spatial substrate.

- Permit heterogeneous channels: a region stores only the state that is meaningful there.

- Support local growth, branching, healing, diffusion, advection, reaction, decay and constraints without explicit mesh topology.

- Expose continuous field evaluation independently of simulation discretisation.

- Make empty-space skipping and conservative ray traversal cheap.

- Allow simulation and rendering to operate at different spatial and temporal resolutions.

- Preserve history as state, enabling structures to embody previous interactions with their environment.

- Scale from small organisms to world-scale coupled field systems.

- Remain renderer-neutral while providing a fast path for Matryoshka.

# 3. Non-goals

- The library is not a scene graph and does not own cameras, lights, BSDF integration or path tracing.

- It does not require a surface mesh or stable topology.

- It does not prescribe biology. Biological morphogenesis is an application built from generic field operators.

- The simulation grid, if any, is not part of the public ontology and must not become the renderer's sampling grid.

- A FieldSample is a logical result, not necessarily the physical in-memory layout of every leaf.

# 4. Conceptual model

A world is a collection of sparse fields F(x,t). A field may describe density, material, temperature, velocity, growth potential, age, chemical concentration, influence, sound energy, or an application-defined quantity. Fields overlap and operators couple them. Persistent state makes the resulting world historical rather than merely procedural.

world fields  
-\> ecological / environmental fields  
-\> organism or process fields  
-\> material / optical fields  
-\> renderer queries F(x,t)

# 5. Core abstractions

## 5.1 Field

A Field is a named collection of spatial channels with sparse support, a coordinate domain, reconstruction rules, versioning, and optional temporal state.

struct FieldHandle;  
struct FieldDescriptor {  
FieldId id;  
AABB domain;  
ChannelMask channels;  
ReconstructionMode reconstruction;  
BoundaryMode boundary;  
};

## 5.2 FieldRegion

A FieldRegion is the spatial storage unit. Regions form a heterogeneous hierarchy (BVH, octree-like hierarchy, or implementation-equivalent structure). Internal nodes carry conservative summaries; leaves carry locally relevant channels and reconstruction data.

struct RegionSummary {  
AABB bounds;  
ChannelMask channels;  
  
Range density;  
Range extinction;  
Range emission;  
float maxGradient;  
float majorant; // optional transport majorant  
uint32_t version;  
};

## 5.3 FieldOperator

A FieldOperator reads one or more fields and emits local updates. Operators are composable and should declare their read/write channel sets and spatial influence.

class FieldOperator {  
public:  
virtual ChannelMask reads() const = 0;  
virtual ChannelMask writes() const = 0;  
virtual void evaluate(const RegionContext&, UpdateBuffer&) = 0;  
};

# 6. Channels and heterogeneous storage

Channels are sparse both spatially and structurally. A leaf containing only density and growth potential must not allocate PBR, velocity, age, temperature, or semantic state. Channel masks permit traversal and update systems to skip irrelevant regions.

enum class Channel : uint64_t {  
Density = 1ull \<\< 0,  
Extinction = 1ull \<\< 1,  
Albedo = 1ull \<\< 2,  
Roughness = 1ull \<\< 3,  
Emission = 1ull \<\< 4,  
Velocity = 1ull \<\< 5,  
Growth = 1ull \<\< 6,  
Temperature = 1ull \<\< 7,  
Age = 1ull \<\< 8,  
Activity = 1ull \<\< 9,  
User0 = 1ull \<\< 32  
};

Application-defined channels should be registered dynamically or through reserved user ranges. The storage backend may use SoA, compressed bricks, procedural coefficients, neural/local basis representations, or mixed encodings on a per-region basis.

# 7. Continuous sampling contract

Consumers query a continuous reconstruction of the field. The implementation may discretise for simulation, but public sampling is expressed in world coordinates.

SampleResult sample(  
FieldHandle field,  
vec3 position,  
float time,  
ChannelMask requestedChannels,  
SampleQuality quality);  
  
float sampleDensity(FieldHandle, vec3 p, float t);  
float sampleExtinction(FieldHandle, vec3 p, float t);  
OpticalSample sampleOptical(FieldHandle, vec3 p, float t);  
MaterialSample sampleMaterial(FieldHandle, vec3 p, float t);

The narrow query functions are important: a shadow ray should not pay to construct semantic or biological state, and a simulation operator should not need renderer-specific material data unless it explicitly reads it.

# 8. Hierarchy and traversal

The hierarchy is a sparse acceleration structure, not the geometry itself. Node summaries must be conservative so consumers can reject regions without leaf sampling.

- Channel mask: reject subtrees that cannot answer the query.

- Density/extinction maxima: skip empty or optically irrelevant space.

- Emission maxima: skip non-emissive regions for emission-specific queries.

- Majorants: support delta/ratio tracking where volumetric transport is used.

- Gradient/error bounds: drive adaptive stepping and refinement.

- Version counters: invalidate cached traversal or temporal reconstruction selectively.

# 9. Evolution model

Evolution is operator-driven. An operator reads the current local state and environmental fields, then proposes changes. Updates are committed in a controlled phase so execution can be parallel, deterministic when requested, and free of accidental order dependence.

for each active region in parallel:  
gather declared input channels  
run scheduled operators  
append changes to region-local UpdateBuffer  
  
barrier / dependency resolution  
  
for each dirty region:  
commit updates  
rebuild conservative summaries  
refine / coarsen if required  
publish new version

# 10. Standard operator set

| Operator   | Typical inputs                         | Effect                                                      |
|------------|----------------------------------------|-------------------------------------------------------------|
| Growth     | growth potential, density, environment | Deposits or transforms persistent state at active fronts.   |
| Diffusion  | scalar/vector channel                  | Spreads a quantity locally.                                 |
| Advection  | field + velocity                       | Transports state through a velocity field.                  |
| Reaction   | two or more channels                   | Transforms coupled quantities according to local kinetics.  |
| Decay      | channel + time                         | Relaxes or removes state.                                   |
| Inhibition | density/activity/neighbours            | Suppresses growth or reaction near occupied/active regions. |
| Healing    | damage/history/target state            | Reactivates local evolution after disruption.               |
| Constraint | geometry/environment/user rule         | Projects or limits state to valid local conditions.         |

# 11. Morphogenesis as an application

An organism is not a special geometry type. It is a bundle of fields and operators. Active fronts move through the domain under environmental gradients and deposit persistent material behind them. Branches, dormancy, repair and tropisms emerge from operator rules and state.

velocity =  
a \* grad(light)  
+ b \* grad(stimulus)  
+ c \* flow  
- d \* grad(self_density)  
+ e \* frontier_normal  
+ noise;  
  
growth = advect(growth, velocity);  
material += deposit(growth, local_resources);  
growth \*= inhibition(material, neighbours);

The important property is that regeneration need not be a separate global program. Damage changes local state; local error or activation can re-enter the same dynamics that originally produced the structure.

# 12. History and residual state

History is represented by ordinary persistent channels rather than an external replay log. Age, damage, previous activity, deposited material, nutrient depletion, stress, or application-defined residuals may alter subsequent evolution. A generated structure therefore records interactions with its environment.

An optional event log may exist for debugging, reproducibility and authoring, but it is not required for the world's history to influence its future.

# 13. Matryoshka rendering interface

Matryoshka should consume the field hierarchy directly enough to exploit conservative summaries, while retaining ownership of transport policy. The field library provides traversal primitives and samples; it does not dictate ray budgets.

struct RayFieldQuery {  
Ray ray;  
float tMin, tMax;  
ChannelMask channels;  
QueryClass queryClass; // primary, shadow, volume, emission...  
float errorTolerance;  
};  
  
TraversalCursor beginTraversal(const RayFieldQuery&);  
bool nextRegion(TraversalCursor&, RegionView&);  
SampleResult sample(const RegionView&, vec3 p, ChannelMask);

Matryoshka may use ray marching, sphere/distance-like stepping where a valid bound exists, empty-space skipping, majorant tracking, cached region cursors, temporal reprojection, or hybrid methods. Stable ray/sample generation is recommended for evolving fields to reduce temporal shimmer.

# 14. Simulation/render decoupling

Simulation resolution and rendering resolution are independent. A coarse simulation region may reconstruct smoothly for rendering; a visually or dynamically important region may refine without changing the public field identity.

- LOD decisions may differ for simulation and rendering.

- Renderer sampling must never mutate simulation state.

- Simulation can update at a lower cadence than rendering.

- Interpolation between published field versions should be supported where meaningful.

- Refinement/coarsening must conserve application-defined invariants where requested.

# 15. Concurrency and snapshots

The preferred model is immutable published snapshots plus mutable construction/update state. Render threads sample a stable version while simulation produces the next version. Dirty-region versioning permits incremental publication and avoids global stalls.

PublishedField\[N\] \<-- render readers  
\|  
simulation reads N  
\|  
UpdateBuffers / dirty regions  
\|  
PublishedField\[N+1\] \<-- atomic publication

# 16. Determinism and reproducibility

Determinism should be selectable. Authoring, testing and networked/world persistence may require reproducible results; exploratory growth may prefer stochastic diversity.

- All stochastic operators accept explicit seeds.

- Per-region random streams derive from stable region identity plus simulation epoch.

- Parallel update order must not silently alter deterministic mode.

- Snapshots carry schema, operator configuration and seed/version metadata sufficient for replay where supported.

# 17. Persistence and streaming

The hierarchy should be serialisable in chunks aligned with spatial regions. Unloaded regions retain conservative metadata sufficient for world streaming decisions. A region's payload may be materialised on demand by simulation, rendering, or editing.

FieldArchive  
header / schema / channel registry  
root summaries  
region directory  
region payloads  
operator state (optional)  
replay/debug metadata (optional)

# 18. Memory and performance principles

- Structure-of-arrays or channel-local blocks are preferred for hot numeric channels.

- Do not instantiate absent channels.

- Quantise or compress cold channels where error bounds permit.

- Keep internal-node summaries compact and cache-friendly.

- Separate hot traversal metadata from cold semantic metadata.

- Batch field queries and operator evaluations for SIMD/GPU execution.

- Treat active-front regions as a sparse working set; dormant historical tissue should be cheap.

- Support CPU and GPU backends without exposing backend-specific storage in the public API.

# 19. Example systems

| System                   | Fields                                    | Operators                                       |
|--------------------------|-------------------------------------------|-------------------------------------------------|
| Organism                 | density, growth, activity, age, velocity  | growth, tropism, inhibition, branching, healing |
| Vegetation               | material, moisture, light, nutrient, age  | growth, diffusion, resource consumption, decay  |
| Fire                     | temperature, fuel, smoke, velocity        | reaction, advection, diffusion, decay           |
| Weather/local atmosphere | temperature, moisture, velocity, pressure | advection, diffusion, reaction                  |
| Corrosion                | material integrity, moisture, chemistry   | reaction, diffusion, decay                      |
| Urban/social influence   | attraction, activity, memory, flow        | diffusion, reinforcement, inhibition, decay     |
| Sound/energy field       | energy, direction, absorption             | propagation/advection, decay, interaction       |

# 20. Proposed C++ surface

namespace matryoshka::fields {  
  
class World {  
public:  
FieldHandle createField(const FieldDescriptor&);  
void destroyField(FieldHandle);  
  
void addOperator(FieldHandle, OperatorHandle);  
void step(const StepContext&);  
  
PublishedSnapshot publish();  
};  
  
class PublishedSnapshot {  
public:  
SampleResult sample(FieldHandle, vec3 p, float t,  
ChannelMask, SampleQuality) const;  
  
TraversalCursor trace(FieldHandle, const RayFieldQuery&) const;  
RegionSummary summary(FieldHandle, RegionId) const;  
};  
  
class OperatorRegistry {  
public:  
OperatorHandle registerOperator(std::unique_ptr\<FieldOperator\>);  
};  
  
} // namespace matryoshka::fields

# 21. Initial implementation plan

- Phase 1 - CPU prototype: sparse 3-D hierarchy, scalar density/growth/light fields, continuous trilinear or higher-order reconstruction, growth/diffusion/advection operators.

- Phase 2 - Matryoshka integration: density/extinction sampling, hierarchical empty-space skipping, simple PBR/material channels, stable temporal sampling.

- Phase 3 - dynamic refinement: error/gradient-driven split and merge, dirty-region summaries, snapshot publication.

- Phase 4 - heterogeneous channels and operator scheduling: declared dependencies, sparse channel blocks, parallel region updates.

- Phase 5 - GPU backend and streaming: batched traversal/sampling, chunk persistence, asynchronous region residency.

- Phase 6 - richer world coupling: light/resource feedback, organisms, weather/material processes, historical residual channels.

# 22. Acceptance tests for the first useful version

- A seeded 3-D growth field creates persistent branching structures without constructing a mesh.

- Moving a light/stimulus field measurably redirects active growth fronts.

- Removing a region of material creates local repair activity without resetting the whole organism.

- Dormant tissue consumes negligible update work until reactivated.

- A Matryoshka ray can skip empty hierarchy nodes using conservative density/extinction summaries.

- Primary and shadow queries request different channel sets and demonstrate reduced sampling work.

- The same field can be rendered at multiple image resolutions without changing simulation resolution.

- A deterministic seed reproduces the same growth history under the same inputs.

- Snapshot N remains safely renderable while snapshot N+1 is being simulated.

# 23. Open design questions

- Which hierarchy best fits the existing heterogeneous Matryoshka BVH: direct reuse, sibling structure, or shared node representation?

- What reconstruction bases give the best quality/cost trade-off per channel: trilinear bricks, splines, local analytic primitives, wavelets, or mixed encodings?

- How should conservative bounds be maintained for procedural/reconstructed leaves?

- Which invariants must refinement conserve for each operator class?

- Should operators run through a fixed scheduler, a dependency graph, or event-driven activation?

- How much semantic/history state belongs in the core library versus application-defined channels?

- What is the cleanest CPU/GPU snapshot representation without coupling the API to either backend?

# 24. Architectural maxim

> **The library does not generate objects. It evolves spatial state. Objects, organisms, materials and environments are interpretations of persistent, interacting fields; Matryoshka merely asks what those fields mean to a ray.**
