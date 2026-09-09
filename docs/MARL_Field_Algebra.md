# MARL Field Algebra

## Differential Operators, Projection, Transport and Coupled Field Dynamics

**Working design note — September 2026**

---

## 1. Motivation

A MARL container can be regarded not merely as a learned approximation to a dataset, but as a **continuous field representation**.

If a MARL represents a field

$$
F : \mathbb{R}^n \rightarrow \mathbb{R}^m,
$$

then its internal kernels provide a compact, spatially organised basis from which the field can be evaluated continuously.

Once two or more such fields exist in the same coordinate domain, an important possibility appears:

> **MARLs can operate mathematically upon other MARLs.**

For example:

* one MARL may represent density;
* another may represent velocity;
* another pressure;
* another temperature;
* another material properties;
* another illumination;
* another a learned environmental force.

Rather than converting these representations back into dense grids, performing a conventional numerical operation, and fitting the result again, it should often be possible to operate **directly upon the continuous representations**.

This suggests a general **MARL Field Algebra**.

The central idea is:

$$
\boxed{
\text{MARL} \xrightarrow{\text{operator}}
\text{continuous field}
\xrightarrow{\text{projection}}
\text{MARL}
}
$$

or, for interactions,

$$
\boxed{
(\text{MARL}_A,\text{MARL}_B)
\xrightarrow{\mathcal O}
\text{MARL}_C
}
$$

where \(\mathcal O\) may be algebraic, differential, geometric, temporal, or learned.

The immediate motivating example is **advection**.

---

# 2. MARL as a Continuous Basis

Consider a scalar MARL field represented locally by kernels

$$
F(x)=\sum_i a_i\phi_i(x),
$$

where:

* \(x\in\mathbb{R}^n\) is position;
* \(\phi_i(x)\) is the spatial response of kernel \(i\);
* \(a_i\) is its coefficient or payload;
* kernels may exist at different scales or levels of the MARL hierarchy.

For a Gaussian/RBF-like kernel,

$$
\phi_i(x)
=
\exp\left(
-\frac{1}{2}
(x-\mu_i)^T
\Sigma_i^{-1}
(x-\mu_i)
\right).
$$

The representation need not literally be this equation internally. What matters for the algebra is that MARL provides:

1. continuous evaluation;
2. spatial locality;
3. preferably analytic or inexpensive derivatives;
4. a mechanism for projecting observations or residuals back into its representation.

These four properties are sufficient to build a useful field calculus.

---

# 3. Scalar, Vector and Tensor MARLs

The payload of a MARL kernel need not be scalar.

A MARL may represent

### Scalar fields

$$
F(x)\in\mathbb{R}
$$

Examples:

* density;
* pressure;
* temperature;
* opacity;
* signed distance;
* chemical concentration.

### Vector fields

$$
V(x)\in\mathbb{R}^n
$$

Examples:

* velocity;
* force;
* displacement;
* surface flow;
* magnetic or electric field approximations.

### Tensor fields

$$
T(x)\in\mathbb{R}^{n\times n}
$$

Examples:

* anisotropic diffusion;
* stress;
* covariance;
* local material response.

This immediately makes MARL considerably more than a compression representation.

It becomes a representation upon which **continuous field mathematics** can be performed.

---

# 4. Primitive Algebraic Operations

The simplest MARL operations are pointwise.

Given

$$
A(x),B(x),
$$

define:

$$
C(x)=A(x)+B(x)
$$

$$
C(x)=A(x)-B(x)
$$

$$
C(x)=A(x)B(x)
$$

$$
C(x)=\alpha A(x)
$$

and, for vector fields,

$$
C(x)=A(x)\cdot B(x)
$$

or

$$
C(x)=A(x)\times B(x).
$$

The result does not necessarily require immediate materialisation.

A useful implementation distinction is therefore between:

### Lazy field expressions

$$
C=A+B
$$

where evaluation of \(C(x)\) evaluates its operands as required;

and:

### Projected fields

$$
C=P(A+B)
$$

where \(P\) approximates the resulting field with a new or existing MARL.

This distinction may become fundamental.

A MARL expression graph could perform substantial field computation before anything is baked back into kernels.

---

# 5. Differential Operators

Because the underlying representation is continuous, derivatives can often be obtained analytically.

For

$$
F(x)=\sum_i a_i\phi_i(x),
$$

the gradient is

$$
\nabla F(x)
=
\sum_i a_i\nabla\phi_i(x).
$$

For an isotropic Gaussian

$$
\phi_i(x)
=
e^{-\|x-\mu_i\|^2/(2\sigma_i^2)},
$$

we have

$$
\nabla\phi_i(x)
=
-\frac{x-\mu_i}{\sigma_i^2}\phi_i(x).
$$

Thus gradient evaluation is approximately the same local operation as field evaluation with a small amount of additional arithmetic.

This gives the first important MARL unary operators:

$$
\nabla F
$$

Gradient.

For a vector MARL \(V\),

$$
\nabla\cdot V
$$

Divergence.

In three dimensions,

$$
\nabla\times V
$$

Curl.

And

$$
\nabla^2F
$$

Laplacian.

Collectively:

$$
\boxed{
\nabla,\quad
\nabla\cdot,\quad
\nabla\times,\quad
\nabla^2
}
$$

form the beginning of a differential calculus directly over MARL fields.

---

# 6. Projection

Projection is the operation that turns an arbitrary continuous result back into a MARL representation.

Define

$$
P_M[G]
$$

as the approximation of field \(G\) in MARL representation \(M\).

Conceptually,

$$
P_M[G]
=
\arg\min_{\hat G\in M}
\|G-\hat G\|.
$$

The exact norm and fitting process can vary.

This is particularly interesting because MARL already possesses machinery for absorbing observations and residuals.

Projection may therefore be implemented through the same mechanisms used during MARL learning.

Rather than treating projection as an entirely new subsystem:

> **MARL learning itself can serve as the projection operator.**

---

# 7. Local Projection

A global least-squares projection could be written as

$$
M a=b
$$

with

$$
M_{ij}
=
\langle\phi_i,\phi_j\rangle
$$

and

$$
b_i
=
\langle\phi_i,G\rangle.
$$

However, a global matrix would throw away one of MARL's most valuable properties: locality.

RBF kernels interact significantly only with nearby kernels.

Therefore:

$$
M_{ij}\approx0
$$

for distant \(i,j\).

Projection should consequently be performed through local neighbourhoods.

For kernel \(i\),

$$
N(i)
=
\{j:\phi_i\text{ substantially overlaps }\phi_j\}.
$$

The update becomes a small local problem rather than a global solve.

This potentially changes the complexity from an operation involving the complete field into one proportional to the number of **active overlapping kernels**.

---

# 8. Advection

Consider a scalar field \(F\) transported by velocity field \(V\).

The classical advection equation is

$$
\frac{\partial F}{\partial t}
+
V\cdot\nabla F
=
0.
$$

Therefore

$$
\frac{\partial F}{\partial t}
=
-V\cdot\nabla F.
$$

For timestep \(\Delta t\),

$$
F_{t+\Delta t}
\approx
F_t
-
\Delta t
(V\cdot\nabla F_t).
$$

If both \(F\) and \(V\) are MARLs,

$$
\boxed{
F'
=
P_F
\left[
F-\Delta t(V\cdot\nabla F)
\right]
}
$$

is a complete MARL advection operator.

Define

$$
\operatorname{Advect}(F,V,\Delta t)
=
P_F[F-\Delta t(V\cdot\nabla F)].
$$

This is the first substantial binary operation in the algebra.

---

# 9. Pressure-Driven Transport

Suppose a second MARL represents pressure

$$
P(x).
$$

A simple velocity field may be derived from its gradient:

$$
V=-k\nabla P.
$$

Substitution gives

$$
\frac{\partial F}{\partial t}
=
k\nabla P\cdot\nabla F.
$$

Therefore

$$
\boxed{
F'
=
P_F
\left[
F+
\Delta t\,k
(\nabla P\cdot\nabla F)
\right]
}
$$

provides direct pressure-driven evolution of one MARL by another.

The important computational property is that neither field needs to be voxelised.

The operation is:

$$
\text{MARL}_P
\rightarrow\nabla P
$$

combined with

$$
\text{MARL}_F
\rightarrow\nabla F,
$$

followed locally by

$$
\nabla P\cdot\nabla F.
$$

This produces a scalar residual which is projected back into \(F\).

---

# 10. Kernel-Level Interaction

Let

$$
F(x)=\sum_j a_j\phi_j(x)
$$

and

$$
P(x)=\sum_k b_k\psi_k(x).
$$

Then

$$
\nabla F
=
\sum_j a_j\nabla\phi_j
$$

and

$$
\nabla P
=
\sum_k b_k\nabla\psi_k.
$$

Therefore

$$
\nabla P\cdot\nabla F
=
\sum_{j,k}
a_jb_k
(\nabla\psi_k\cdot\nabla\phi_j).
$$

Projected onto receiving kernel \(i\),

$$
\dot a_i
\approx
k
\sum_{j,k\in N(i)}
a_jb_k
\left\langle
\phi_i,
\nabla\psi_k\cdot\nabla\phi_j
\right\rangle.
$$

This is particularly interesting.

The dynamics reduce to **local kernel interactions**.

If kernel shapes come from a limited family, much of

$$
\left\langle
\phi_i,
\nabla\psi_k\cdot\nabla\phi_j
\right\rangle
$$

may be determined by:

* relative displacement;
* relative scale;
* orientation;
* covariance;
* kernel family.

Those interactions may therefore be analytically simplified, cached, tabulated, or approximated.

A simulation step could eventually resemble a sparse kernel interaction pass rather than conventional field simulation.

---

# 11. Semi-Lagrangian MARL Advection

The differential form is not the only possibility.

Conventional fluid simulation often uses backward tracing:

$$
F_{t+\Delta t}(x)
=
F_t(x-\Delta t V(x)).
$$

MARL makes this unusually attractive because \(F\) is already continuously queryable.

For every projection point \(x_i\):

1. evaluate

$$
V_i=V(x_i);
$$

2. backtrace

$$
x_i'=x_i-\Delta t V_i;
$$

3. query

$$
y_i=F(x_i');
$$

4. project \(y_i\) into the receiving MARL.

Thus

$$
\boxed{
\operatorname{Advect}_{SL}(F,V)
=
P_F
\left[
x\mapsto F(x-\Delta tV(x))
\right].
}
$$

This may prove considerably more numerically stable than explicit Euler differential advection.

It should probably be one of the **first experimental implementations**.

---

# 12. Projection Points Need Not Form a Grid

A significant advantage of MARL is that projection samples do not need to occupy a uniform lattice.

Useful candidates include:

* kernel centres;
* kernel centres plus derivative probes;
* existing measurements;
* adaptive high-error locations;
* overlapping-kernel centroids;
* stochastic importance samples;
* dynamically generated residual maxima.

This suggests:

$$
\text{compute where information exists}
$$

rather than

$$
\text{compute everywhere because a grid exists}.
$$

Regions represented by large smooth kernels may require very little work.

Complex regions automatically receive more computation because MARL has already allocated more representational structure there.

The simulation resolution therefore naturally follows the **information density of the field**.

---

# 13. Conservation

Naïve projection may introduce drift in quantities that should be conserved.

For a density field, for example,

$$
M=\int F(x)\,dx
$$

may represent total mass.

After an update,

$$
\int F'(x)\,dx
$$

should ideally equal the original mass unless the model explicitly contains sources or sinks.

This suggests constrained projection:

$$
P_M^C[G]
$$

where \(C\) specifies invariants.

Examples include:

$$
\int F\,dx=M_0
$$

for mass;

$$
\int FV\,dx=p_0
$$

for momentum;

or other application-specific quantities.

A practical early implementation may simply measure the conserved quantity before and after projection and apply a correction.

Later, conservation can become part of the local projection solve itself.

---

# 14. Diffusion

The diffusion equation is

$$
\frac{\partial F}{\partial t}
=
D\nabla^2F.
$$

Therefore:

$$
\boxed{
F'
=
P_F
[
F+\Delta tD\nabla^2F
]
}
$$

defines a MARL diffusion operator.

This is particularly attractive because the Laplacian of an RBF is analytic.

Possible uses include:

* heat propagation;
* smoke dispersion;
* chemical concentration;
* moisture;
* light diffusion approximations;
* smoothing;
* regularisation.

---

# 15. Reaction-Diffusion

Given fields \(A\) and \(B\),

$$
\frac{\partial A}{\partial t}
=
D_A\nabla^2A+R_A(A,B)
$$

$$
\frac{\partial B}{\partial t}
=
D_B\nabla^2B+R_B(A,B).
$$

MARL therefore naturally supports:

$$
A'
=
P[
A+\Delta t(D_A\nabla^2A+R_A(A,B))
]
$$

and similarly for \(B\).

This creates a compact continuous substrate for:

* chemical patterns;
* biological morphogenesis;
* corrosion;
* vegetation;
* fire;
* procedural texture evolution.

---

# 16. Source and Sink Operators

Introduce a source field \(S\):

$$
\frac{\partial F}{\partial t}=S.
$$

Then

$$
F'=P[F+\Delta tS].
$$

Similarly, decay may be represented by

$$
\frac{\partial F}{\partial t}=-\lambda F
$$

giving

$$
F'=P[F(1-\lambda\Delta t)]
$$

or analytically,

$$
F'=P[Fe^{-\lambda\Delta t}].
$$

These trivial operations become surprisingly useful when composed with transport and diffusion.

---

# 17. General Evolution Equation

Many simulations can now be expressed as:

$$
\boxed{
\frac{\partial F}{\partial t}
=
\mathcal{L}(F,G,H,\ldots)
}
$$

where \(\mathcal L\) is constructed from MARL algebra operators.

For example,

$$
\mathcal L
=
-V\cdot\nabla F
+
D\nabla^2F
+
S
-
\lambda F.
$$

Hence:

$$
F'
=
P_F[
F+\Delta t\mathcal L
].
$$

This gives a general MARL field evolution model:

$$
\boxed{
F_{t+\Delta t}
=
P_F
[
F_t+\Delta t\,
\mathcal L(F_t,\ldots)
]
}
$$

The field representation and the dynamics are now cleanly separated.

---

# 18. A Small Operator Vocabulary

An initial MARL algebra could expose something conceptually like:

```text
sample(F, x)

gradient(F)
divergence(V)
curl(V)
laplacian(F)

add(A, B)
subtract(A, B)
multiply(A, B)
dot(A, B)
cross(A, B)

project(expr, target)

advect(F, V, dt)
diffuse(F, D, dt)
decay(F, lambda, dt)

source(F, S, dt)
relax(F, target, rate, dt)

compose(...)
step(...)
```

For example:

```text
velocity = -gradient(pressure)

density =
    advect(density, velocity, dt)

temperature =
    advect(temperature, velocity, dt)

temperature =
    diffuse(temperature, thermalDiffusion, dt)
```

The API begins to resemble a **shader language for continuous learned fields**.

That may be a useful architectural analogy.

---

# 19. Lazy MARL Expression Graphs

There is no requirement that every intermediate expression become another MARL.

For example,

```text
gradient(pressure)
```

may simply create a lazy field evaluator.

Likewise:

```text
dot(
    gradient(pressure),
    gradient(density)
)
```

could remain an expression graph until projected.

Thus:

```text
density += project(
    dt * k *
    dot(
        gradient(pressure),
        gradient(density)
    )
)
```

could potentially compile into one fused traversal of the relevant MARL neighbourhoods.

This avoids:

* intermediate MARLs;
* unnecessary allocations;
* repeated tree traversal;
* redundant kernel evaluation.

The algebra can therefore double as an **optimisation IR**.

---

# 20. Operator Fusion

Consider:

$$
F'
=
F+
\Delta t
[
-V\cdot\nabla F
+
D\nabla^2F
+
S
].
$$

A naïve implementation might independently evaluate:

1. gradient;
2. advection;
3. Laplacian;
4. source;
5. projection.

A fused implementation visits an active neighbourhood once and accumulates all required terms.

Conceptually:

```text
for active region:
    f    = F.sample(...)
    grad = F.gradient(...)
    lap  = F.laplacian(...)
    vel  = V.sample(...)
    src  = S.sample(...)

    residual =
        -dot(vel, grad)
        + D * lap
        + src

    F.projectResidual(residual * dt)
```

This is potentially extremely GPU-friendly.

---

# 21. Adaptive Temporal Resolution

Spatial adaptivity suggests temporal adaptivity.

Regions where

$$
\left|\frac{\partial F}{\partial t}\right|
$$

is small do not need frequent updates.

Regions with large residuals do.

Therefore individual MARL regions could possess local update schedules based upon:

* velocity;
* gradient magnitude;
* curvature;
* residual;
* kernel scale;
* estimated local truncation error.

This suggests an asynchronous simulation in which different parts of the field evolve at different rates.

A nearly static region might sleep for many frames.

A turbulent boundary might update continuously.

The simulation cost would then track **spatiotemporal complexity**, rather than world volume multiplied by frame rate.

---

# 22. Relationship to MARL Responsibility

The existing MARL responsibility machinery may be especially useful here.

An operator generates evidence:

$$
r(x)=\mathcal L(F,\ldots).
$$

Rather than broadcasting this update indiscriminately through the hierarchy, responsibility can determine which kernels should absorb it.

This creates a pleasing symmetry:

> The same mechanism that decides where MARL should learn a field can decide where MARL should evolve a field.

Large-scale changes may be absorbed by coarse kernels.

Fine local dynamics may be absorbed by finer kernels.

The hierarchy itself becomes part of the numerical method.

---

# 23. Distillation as Simulation Consolidation

Repeated dynamic updates may gradually produce a representation that is locally useful but structurally untidy.

The MARL distillation mechanism provides a natural answer.

After some period of evolution:

$$
M_t
\xrightarrow{\text{distil}}
\tilde M_t.
$$

The student approximates the evolved teacher while potentially obtaining:

* fewer kernels;
* lower approximation error;
* improved responsibility allocation;
* reduced historical clutter.

Thus the previously proposed analogy with sleep becomes directly relevant to simulation.

Simulation creates local representational edits.

Distillation periodically consolidates them.

A dynamic MARL system could therefore alternate:

$$
\boxed{
\text{evolve}
\rightarrow
\text{evolve}
\rightarrow
\text{evolve}
\rightarrow
\text{consolidate}
\rightarrow\cdots
}
$$

This may permit indefinitely evolving fields without indefinite structural degradation.

---

# 24. Stacked MARLs

Static and dynamic information need not occupy the same MARL.

Let

$$
F(x,t)
=
F_{\text{static}}(x)
+
F_{\text{dynamic}}(x,t).
$$

This directly connects to stacked MARLs.

A base MARL may represent:

* terrain;
* buildings;
* static geometry;
* persistent material properties.

Overlay MARLs may represent:

* moving objects;
* fluid;
* temperature;
* illumination changes;
* transient particles;
* damage;
* weather.

Operators may act upon selected layers without touching others.

For example:

$$
\text{wind}
\curvearrowright
\text{smoke}
$$

while the static environment remains unchanged.

This permits extremely cheap dynamic overlays over a large persistent world representation.

---

# 25. Cross-MARL Coupling

The deeper implication is that fields can mutually influence one another.

For example:

$$
V \rightarrow F
$$

through advection,

while

$$
F \rightarrow V
$$

through buoyancy or drag.

A temperature MARL might affect velocity:

$$
V'
=
V+\Delta t\,\beta(T-T_0)\hat y.
$$

Velocity then transports temperature:

$$
T'
=
\operatorname{Advect}(T,V).
$$

This creates a coupled dynamical system:

$$
\boxed{
M_1
\leftrightarrow
M_2
\leftrightarrow
M_3
\ldots
}
$$

MARLs cease to be passive containers.

They become interacting state variables.

---

# 26. Example: Fire and Smoke

Consider:

* \(F\): fuel;
* \(T\): temperature;
* \(S\): smoke density;
* \(V\): velocity.

Combustion might produce

$$
R=kF\,g(T).
$$

Then:

$$
F_t=-R
$$

$$
T_t=qR-\lambda_TT+D_T\nabla^2T
$$

$$
S_t=\alpha R-\lambda_SS-V\cdot\nabla S
$$

and velocity may receive buoyancy:

$$
V_t
=
\beta(T-T_0)\hat y.
$$

Every quantity is a MARL.

The fire system becomes a graph of field interactions rather than a voxel simulation.

This connects directly with evolving RBF particle fields: particles may inject observations into these MARLs while the MARLs provide continuous environmental fields back to the particles.

---

# 27. Example: Fluid-Like Fields

A complete Navier–Stokes solver is considerably more demanding, particularly because incompressibility requires solving a pressure Poisson equation.

Nevertheless, many components already fit naturally:

Advection:

$$
V_t=-(V\cdot\nabla)V
$$

Viscosity:

$$
V_t=\nu\nabla^2V
$$

External forces:

$$
V_t=F.
$$

Pressure correction requires:

$$
\nabla^2P
=
\frac{1}{\Delta t}
\nabla\cdot V^*
$$

followed by

$$
V
=
V^*
-
\Delta t\nabla P.
$$

This raises a particularly interesting future research question:

> Can the MARL hierarchy itself provide an efficient multiscale pressure solve?

Because MARL already contains coarse-to-fine spatial structure, it may have properties analogous to those deliberately constructed by multigrid methods.

This should be treated as a research direction rather than assumed, but it is an unusually attractive one.

---

# 28. Example: Irradiance

Let a MARL represent an irradiance field

$$
L(x).
$$

Dynamic objects or lights create another field

$$
E(x).
$$

A relaxation process might approximate propagation:

$$
L_t
=
D\nabla^2L
+
E
-
\lambda L.
$$

Although this is not a replacement for physically exact light transport, it may provide useful slowly varying indirect illumination fields.

Dynamic MARL overlays could then represent changes caused by:

* moving lights;
* doors opening;
* emissive particles;
* fire;
* time of day.

The field need only update significantly where illumination actually changes.

---

# 29. Example: Procedural Weather

Separate MARLs could represent:

* pressure;
* temperature;
* humidity;
* wind;
* cloud density.

For example,

$$
V=-k\nabla P
$$

drives transport of

$$
H
$$

and

$$
T.
$$

Condensation can become a reaction term where temperature and humidity satisfy appropriate conditions.

The objective need not be meteorological accuracy.

For a world engine, the important result may be **spatially coherent emergent weather** generated from interacting continuous fields.

---

# 30. Example: Morphogenesis and Loam

The same algebra naturally applies to Loam-like growth.

Fields might represent:

* nutrients;
* occupancy;
* attraction;
* inhibition;
* moisture;
* light;
* growth potential.

Growth can follow gradients:

$$
V_g
=
\alpha\nabla N
-
\beta\nabla I
+
\gamma\nabla L.
$$

Reaction-diffusion fields can establish morphology.

Geometry then grows through the resulting field.

Instead of encoding every growth rule explicitly, Loam could grow inside a continuously evolving **field ecology**.

---

# 31. Example: Particles as Field Probes and Actuators

Particles and MARLs are particularly complementary.

Particles can **read** MARLs:

$$
V_p += F(x_p)\Delta t
$$

and can **write** MARLs:

$$
M.\operatorname{observe}(x_p,q_p).
$$

This produces a bidirectional relationship:

$$
\boxed{
\text{Particles}
\leftrightarrow
\text{MARL fields}
}
$$

A fire particle can deposit heat.

The heat field creates buoyancy.

The buoyancy field moves smoke particles.

Smoke particles deposit density.

Density modifies illumination.

The result is not a conventional particle system with a collection of independent handcrafted operators.

It is a small ecosystem of interacting continuous fields.

---

# 32. Geometry as a Field Participant

Once geometry has itself been represented or distilled into MARL form, geometry can participate in the same algebra.

A geometric MARL could provide:

* occupancy;
* signed distance;
* normals;
* material properties;
* permeability;
* collision gradients.

A fluid MARL can therefore interact directly with a geometry MARL.

For signed distance field \(D(x)\),

$$
n(x)
=
\frac{\nabla D}{\|\nabla D\|}.
$$

Velocity approaching the boundary may be projected:

$$
V'
=
V-
\min(0,V\cdot n)n.
$$

Thus collision and boundary response can themselves become field operations.

This links directly to the proposal to distil Gaussian splats into MARL representations.

The same representation used for rendering could begin to participate in simulation.

---

# 33. Higher-Dimensional MARLs

Nothing in the algebra fundamentally requires three dimensions.

A MARL may represent

$$
F(x,y,z,t)
$$

or more generally

$$
F:\mathbb R^n\rightarrow\mathbb R^m.
$$

Additional dimensions might encode:

* time;
* wavelength;
* direction;
* material state;
* phase;
* latent variables.

This opens another possibility.

Rather than numerically evolving

$$
F(x,t)
$$

one timestep at a time, a higher-dimensional MARL may learn portions of the spacetime solution itself.

Then temporal derivatives become simply another analytic derivative:

$$
\frac{\partial F}{\partial t}.
$$

The distinction between **representation** and **simulation history** begins to blur.

---

# 34. A General MARL Operator Form

The algebra can be summarised as operators

$$
\mathcal O:
(M_1,M_2,\ldots,M_n)
\rightarrow M'
$$

with optional projection:

$$
M'
=
P[
\mathcal O(M_1,\ldots,M_n)
].
$$

Useful operator classes are:

### Algebraic

$$
+,-,\times,\div,\cdot,\times
$$

### Differential

$$
\nabla,\nabla\cdot,\nabla\times,\nabla^2
$$

### Geometric

$$
\operatorname{warp},
\operatorname{transform},
\operatorname{project},
\operatorname{distance}
$$

### Temporal

$$
\operatorname{advect},
\operatorname{diffuse},
\operatorname{decay},
\operatorname{relax},
\operatorname{integrate}
$$

### Structural

$$
\operatorname{distil},
\operatorname{merge},
\operatorname{split},
\operatorname{overlay}
$$

### Constraint

$$
\operatorname{conserve},
\operatorname{clamp},
\operatorname{boundary},
\operatorname{normalise}
$$

This is sufficiently small to form an initial language while being expressive enough to describe surprisingly complex systems.

---

# 35. Proposed First Experiment

The first experiment should be deliberately simple.

Do **not** begin with Navier–Stokes.

Use two 2D MARLs.

### MARL A — transported scalar

Construct a smooth blob:

$$
F(x,y)
=
e^{-(x^2+y^2)/r^2}.
$$

### MARL B — velocity

Construct a rotational vector field:

$$
V(x,y)
=
(-y,x).
$$

Then perform semi-Lagrangian advection:

$$
F'(x)
=
F(x-\Delta tV(x)).
$$

At each MARL-A kernel centre:

1. evaluate \(V(x_i)\);
2. backtrace to \(x_i'\);
3. evaluate old \(F(x_i')\);
4. feed that value into the projection/update mechanism;
5. render;
6. repeat.

Expected result:

> The scalar blob should rotate around the origin while retaining approximately its shape.

Measure:

* RMS error against an analytic rotation;
* kernel count;
* projection work;
* mass drift;
* update count per kernel;
* runtime per step;
* error accumulation over many rotations.

This provides a beautifully clean benchmark because the exact solution is known.

---

# 36. Second Experiment: Pressure Gradient

Once rotation works:

Construct a scalar pressure MARL \(P\).

Derive

$$
V=-k\nabla P.
$$

Use it to transport \(F\).

This tests:

* analytic MARL gradients;
* MARL-to-MARL coupling;
* derived fields;
* projection stability.

Render:

* pressure;
* pressure gradient;
* velocity;
* transported scalar.

If this works, the essential hypothesis behind MARL field algebra has been demonstrated.

---

# 37. Third Experiment: Advection + Diffusion

Add

$$
D\nabla^2F.
$$

Now compare:

$$
F_t
=
-V\cdot\nabla F
+
D\nabla^2F.
$$

This tests whether multiple operators can be fused into a single residual update.

It is also the point where the expression-graph architecture starts becoming worthwhile.

---

# 38. Fourth Experiment: Conservation

Measure

$$
M_t=\int F_t(x)\,dx.
$$

Watch how it evolves under repeated projection.

If significant drift appears:

1. measure it;
2. introduce global correction;
3. later investigate local conservative projection.

Do not solve conservation prematurely.

First establish how serious the problem actually is.

---

# 39. Fifth Experiment: Dynamic Responsibility

Compare:

1. updating every kernel;
2. updating kernels with significant local velocity;
3. updating kernels with significant predicted residual;
4. allowing responsibility to select receiving kernels.

Measure error against work.

This experiment is particularly important because the real promise of the approach is not simply that MARL can simulate a field.

A grid can already do that extremely well.

The interesting hypothesis is:

$$
\boxed{
\text{simulation cost}
\propto
\text{information change}
}
$$

rather than

$$
\boxed{
\text{simulation cost}
\propto
\text{domain volume}.
}
$$

That is the claim worth testing.

---

# 40. What Would Constitute Success?

The first prototype does not need to outperform a CUDA grid solver.

Success would be demonstrating that:

1. one MARL can mathematically drive another;
2. derivatives can be obtained cheaply from the representation;
3. the result can be projected without catastrophic degradation;
4. repeated evolution remains stable;
5. work concentrates naturally in complex or changing regions;
6. distillation can recover representational quality after prolonged evolution.

If those properties hold, optimisation comes later.

The conceptual result would already be significant:

> **MARL would have evolved from an adaptive field representation into an adaptive field-computation substrate.**

---

# 41. Longer-Term Architectural Possibility

There is a larger architecture hiding behind these experiments.

Imagine a world represented as a collection of MARL fields:

```text
Geometry
Material
Velocity
Pressure
Temperature
Humidity
Smoke
Light
Sound
Occupancy
Growth
Agents
```

Relations between them form an operator graph:

```text
Pressure ──gradient──▶ Velocity
                         │
                         ├──advect──▶ Smoke
                         ├──advect──▶ Heat
                         └──force───▶ Particles

Heat ─────buoyancy────▶ Velocity
Fire ─────source──────▶ Heat
Fire ─────source──────▶ Smoke

Geometry ─boundary────▶ Velocity
Geometry ─occlusion───▶ Light

Light ─────gradient───▶ Growth
Moisture ─────────────▶ Growth
```

The world is no longer primarily a collection of arrays being stepped by unrelated simulation systems.

It becomes a graph of continuous fields transforming and influencing one another.

And because all of those fields share the MARL representation, they share:

* spatial indexing;
* adaptive resolution;
* projection;
* responsibility;
* residual learning;
* hierarchy;
* distillation;
* potentially the same GPU execution machinery.

That common substrate may ultimately be more important than any individual operator.

---

# 42. Core Hypothesis

The central research hypothesis can therefore be stated succinctly:

$$
\boxed{
\text{Adaptive representation}
+
\text{analytic field operators}
+
\text{local projection}
=
\text{adaptive computation}
}
$$

MARL began as a way of asking:

> **How little representation is required to describe this field?**

The algebra extends that question to dynamics:

> **How little computation is required to evolve this field?**

If the second answer inherits the same locality, hierarchy and adaptive responsibility that made the first successful, MARL may provide a unified representation and computation model for sparse, continuous, evolving worlds.

That is the experiment worth doing.
