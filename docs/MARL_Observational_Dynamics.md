# MARL Observational Dynamics

## Learning Continuous Fields, Hidden State and Dynamics from Observation

**Working design note — September 2026**

---

## 1. Motivation

MARL Field Algebra introduces the possibility of evolving continuous MARL fields through operators such as:

$$
\nabla,\qquad
\nabla^2,\qquad
\operatorname{advect},\qquad
\operatorname{diffuse},\qquad
\operatorname{project}.
$$

This provides a forward model:

$$
M_t
\xrightarrow{\Phi}
M_{t+\Delta t}
$$

where \(\Phi\) is an expression graph describing the field dynamics.

However, a more important possibility follows.

If the evolving system can be observed, observations can be compared with predictions and the resulting error propagated **backwards through the MARL field and its operator graph**.

The system therefore becomes:

$$
\boxed{
\text{predict}
\rightarrow
\text{observe}
\rightarrow
\text{residual}
\rightarrow
\text{attribute}
\rightarrow
\text{learn}
}
$$

MARL is no longer merely representing or simulating a field.

It is continually learning what the field must be in order to explain reality.

---

# 2. The Basic Observational Loop

Let the current MARL state be

$$
M_t.
$$

A dynamical operator graph predicts:

$$
\hat M_{t+\Delta t}
=
\Phi(M_t,\Delta t).
$$

An observation process \(H\) maps the predicted continuous field into something measurable:

$$
\hat y_k
=
H_k(\hat M_{t+\Delta t}).
$$

Reality provides:

$$
y_k.
$$

The innovation or observational residual is therefore:

$$
r_k
=
y_k-\hat y_k.
$$

This residual becomes new evidence.

Instead of merely recording the discrepancy, MARL asks:

> Which parts of the representation were responsible for this prediction?

The residual can then be propagated back through those responsible components.

---

# 3. Responsibility as Credit Assignment

Suppose the predicted field value at \(x\) is

$$
F(x)=\sum_i a_i\phi_i(x).
$$

An observation at \(x_k\) depends primarily upon kernels whose support overlaps \(x_k\).

Their contribution can be estimated directly.

For a simple scalar observation,

$$
\frac{\partial F(x_k)}{\partial a_i}
=
\phi_i(x_k).
$$

Therefore an observational residual naturally provides a coefficient update direction.

But MARL contains richer parameters than coefficients alone.

A kernel may possess:

$$
\theta_i=
\{a_i,\mu_i,\Sigma_i,\ldots\}.
$$

The residual may therefore produce gradients such as:

$$
\frac{\partial L}{\partial a_i},
\qquad
\frac{\partial L}{\partial \mu_i},
\qquad
\frac{\partial L}{\partial \Sigma_i}.
$$

The observation can potentially modify:

* kernel value;
* kernel position;
* kernel extent;
* anisotropy;
* hierarchy;
* responsibility;
* structural allocation.

This means MARL can change not merely its answer, but **how it represents the region responsible for the error**.

---

# 4. Backpropagation Through MARL Space

Consider a loss

$$
L(y,\hat y).
$$

The predicted observation depends upon the MARL:

$$
\hat y=H(M).
$$

Then

$$
\frac{\partial L}{\partial\theta_i}
=
\frac{\partial L}{\partial\hat y}
\frac{\partial\hat y}{\partial M}
\frac{\partial M}{\partial\theta_i}.
$$

Because the MARL field representation is analytic, many of these derivatives are directly available.

This suggests a form of **backpropagation through continuous MARL space**.

Importantly, this does not imply blindly updating every kernel.

MARL's existing locality and responsibility machinery can determine which parts of the hierarchy should receive the evidence.

Thus gradient information and MARL responsibility can cooperate:

$$
\boxed{
\text{gradient}
\times
\text{responsibility}
\rightarrow
\text{local update}
}
$$

---

# 5. Backpropagation Through Field Algebra

The idea becomes substantially more powerful when observations depend indirectly upon a MARL field.

Consider:

$$
M
\xrightarrow{\nabla}
G
\xrightarrow{\Phi}
X
\xrightarrow{H}
\hat y.
$$

For example:

* \(M\) represents gravitational potential;
* \(\nabla M\) produces acceleration;
* acceleration evolves a body's trajectory;
* a telescope observes its apparent position.

The loss gradient becomes:

$$
\frac{\partial L}{\partial M}
=
\frac{\partial L}{\partial\hat y}
\frac{\partial\hat y}{\partial X}
\frac{\partial X}{\partial G}
\frac{\partial G}{\partial M}.
$$

Thus an error in an observed trajectory can modify the **underlying continuous field responsible for producing it**.

The lazy MARL expression graph therefore has a second purpose.

It is not merely an optimisation IR for forward computation.

It is also a computational graph for inverse inference.

---

# 6. The Expression Graph Becomes Bidirectional

Forward:

$$
M
\rightarrow
\nabla M
\rightarrow
\text{dynamics}
\rightarrow
\text{prediction}.
$$

Backward:

$$
\text{observation residual}
\rightarrow
\text{dynamics}
\rightarrow
\nabla M
\rightarrow
M.
$$

Thus:

$$
\boxed{
\text{MARL Algebra}
=
\text{forward field computation}
+
\text{backward field inference}
}
$$

This greatly increases the significance of retaining the algebra as a declarative graph rather than immediately executing every operator.

The graph describes not merely how to compute the world forward, but how evidence can travel backwards through the model.

---

# 7. Learning Hidden Fields

Suppose the true field \(F^*(x)\) is unknown.

We cannot directly measure it.

We can only observe entities affected by it.

For example:

$$
F^*
\rightarrow
\text{object dynamics}
\rightarrow
\text{observed trajectories}.
$$

Start with an approximate MARL:

$$
F_0(x).
$$

Use it to predict trajectories.

Compare those predictions against observations.

Then optimise:

$$
F_{n+1}
=
F_n
-
\eta
\frac{\partial L}{\partial F_n}.
$$

The resulting MARL becomes a continuous reconstruction of the hidden field.

This is an inverse problem performed directly in adaptive continuous field space.

---

# 8. Sparse Observation

The observation does not need to cover the complete field.

Suppose measurements exist only at

$$
x_1,x_2,\ldots,x_N.
$$

MARL can still construct a continuous representation because each observation contributes evidence to overlapping kernels.

The hierarchy determines how broadly that evidence should generalise.

Sparse observations may initially modify coarse kernels.

As evidence accumulates and contradictions appear, finer structure can emerge.

This creates a particularly interesting interpretation:

> MARL resolution becomes proportional not merely to geometric complexity, but to **observational necessity**.

Regions poorly constrained by observations can remain coarse.

Regions where observations demand additional explanatory structure can refine.

---

# 9. Field Moments Across Scale

The MARL hierarchy provides something conventional state estimation does not naturally expose: an explicit scale dimension.

Let

$$
E(x,s,t)
$$

represent residual, activity, responsibility or representational effort at position \(x\), scale \(s\), and time \(t\).

We can therefore observe:

* where prediction fails;
* when prediction fails;
* at what scale prediction fails;
* how the failure migrates through scale;
* how the hierarchy reorganises in response.

This effectively provides a **scale-space view of model difficulty**.

For a chaotic dynamical system, that may be extremely informative.

---

# 10. Physical State and Representational State

A MARL dynamical system exposes two related systems.

### Physical state

Examples:

$$
F(x,t),
\quad
\nabla F,
\quad
V(x,t),
\quad
x_i(t).
$$

### Representational state

Examples:

$$
R(x,s,t)
$$

for responsibility,

$$
E(x,s,t)
$$

for residual,

$$
K(x,s,t)
$$

for kernel density,

along with:

* refinement events;
* kernel births;
* kernel deaths;
* scale transitions;
* update frequency;
* distillation edits.

Thus:

$$
\boxed{
\text{observable system}
=
\text{physical dynamics}
+
\text{representational dynamics}
}
$$

The representation's behaviour may itself become a diagnostic instrument.

---

# 11. Chaos as Representational Dynamics

MARL does not make a chaotic system analytically predictable.

Small uncertainties still grow.

However, MARL may expose **where and at what scale predictive difficulty develops**.

Consider a three-body system.

When bodies are distant and dynamics are smooth, the field may be represented by relatively coarse structure.

During a close encounter:

* gradients steepen;
* residual increases;
* responsibility concentrates;
* finer kernels activate;
* update rates rise;
* the hierarchy restructures.

Afterwards, unnecessary complexity may collapse or be removed through distillation.

Thus a close encounter produces not merely a trajectory event, but a measurable **representational event**.

This raises an important research question:

> Does representational change contain useful precursors to macroscopic instability?

---

# 12. An Endogenous Complexity Instrument

Define some local measure of MARL effort:

$$
C(x,s,t)
=
f(
\text{residual},
\text{updates},
\text{refinement},
\text{responsibility},
\text{kernel density}
).
$$

This is not necessarily a formal measure of physical entropy or Lyapunov instability.

It should not initially be interpreted as one.

Instead, it is an empirical measure of:

> **How much representational work MARL requires to explain this region at this scale.**

That quantity may itself prove useful.

One could compare it with:

* curvature;
* field gradients;
* trajectory divergence;
* local Lyapunov estimates;
* prediction uncertainty;
* physical energy transfer.

The correlations may reveal whether MARL's internal adaptation is measuring something physically meaningful.

---

# 13. Observation Versus Prediction

Because observations continuously enter the system, MARL can maintain two conceptually distinct states:

$$
M_{\text{predicted}}
$$

and

$$
M_{\text{corrected}}.
$$

Their difference is itself informative:

$$
\Delta M
=
M_{\text{corrected}}
-
M_{\text{predicted}}.
$$

This represents the portion of reality the current dynamical model failed to explain.

Over time, persistent structure in \(\Delta M\) may indicate:

* incorrect initial conditions;
* missing forces;
* incorrect parameters;
* unmodelled objects;
* incorrect boundary conditions;
* an incomplete physical law.

This turns residuals from numerical nuisances into scientific evidence.

---

# 14. State Learning

The simplest learning mode updates only the current field state.

Let the dynamics remain fixed:

$$
M_{t+1}=\Phi(M_t;\theta).
$$

Observations correct \(M\), while \(\theta\) remains unchanged.

This answers:

> **What state of the field best explains the observations under our assumed dynamics?**

This should be the first observational implementation.

---

# 15. Parameter Learning

The next level allows observations to update parameters of the dynamics.

Suppose:

$$
M_{t+1}
=
\Phi(M_t;\theta)
$$

where \(\theta\) may contain:

* masses;
* gravitational constant;
* viscosity;
* diffusion coefficients;
* drag;
* source strengths;
* material parameters.

Then:

$$
\frac{\partial L}{\partial\theta}
$$

can be obtained by differentiating through the operator graph.

Now the system asks:

> **Which parameters make the assumed law best explain reality?**

This is continuous system identification.

---

# 16. Law Learning

A more speculative stage allows the structure of \(\Phi\) itself to change.

Suppose the assumed dynamics are:

$$
F_t
=
\mathcal L(F;\theta).
$$

Persistent structured residuals may suggest that \(\mathcal L\) is incomplete.

Candidate operators could be introduced and tested:

$$
F_t
=
\mathcal L(F)
+
\alpha O_1(F)
+
\beta O_2(F).
$$

If observations consistently drive

$$
\alpha\rightarrow0,
$$

the candidate contributes little.

If another operator consistently reduces predictive error, it may represent missing dynamics.

Thus MARL algebra potentially provides a vocabulary for **discovering equations from observations**.

This is a considerably later research direction, but the architecture naturally points toward it.

---

# 17. Observation as Another Field

Observations themselves may be represented as MARLs.

For example:

$$
O(x,t)
$$

could encode measured evidence and confidence.

Prediction gives:

$$
P(x,t).
$$

Residual becomes:

$$
R(x,t)
=
O(x,t)-P(x,t).
$$

Confidence can weight projection:

$$
\Delta M
=
P_M[
W(x,t)R(x,t)
].
$$

This allows heterogeneous sensors to contribute continuous evidence with different confidence levels.

---

# 18. Multi-Sensor Fusion

Consider:

* camera observations;
* depth;
* radar;
* lidar;
* temperature;
* pressure;
* particle measurements;
* astronomical observations.

Each sensor has an observation operator:

$$
H_1,H_2,\ldots,H_n.
$$

Each produces residual:

$$
r_i
=
y_i-H_i(M).
$$

The combined objective may be:

$$
L
=
\sum_i w_iL_i.
$$

Backpropagation then allows all sensors to modify a shared underlying continuous field.

The field becomes the common explanatory substrate connecting heterogeneous observations.

---

# 19. Temporal Backpropagation

An observation at time \(t_n\) may reveal that the field was wrong at an earlier time.

Given:

$$
M_0
\xrightarrow{\Phi}
M_1
\xrightarrow{\Phi}
M_2
\rightarrow\cdots\rightarrow
M_n,
$$

an observational loss at \(M_n\) can theoretically propagate backwards:

$$
\frac{\partial L_n}{\partial M_0}.
$$

This is backpropagation through the simulated dynamics.

For long chaotic trajectories this will become numerically difficult, and naive differentiation may be impractical.

However, shorter windows may be extremely useful.

This suggests **temporal assimilation windows**:

1. predict forward for a bounded interval;
2. collect observations;
3. compute residuals;
4. propagate evidence backwards through the interval;
5. update the MARL;
6. continue.

This resembles ideas from data assimilation and differentiable simulation, but occurs directly within MARL's adaptive field representation.

---

# 20. Distillation as Observational Consolidation

After repeated observational corrections, the MARL may accumulate representational history.

Distillation can consolidate this learned state.

Thus:

$$
\text{predict}
\rightarrow
\text{observe}
\rightarrow
\text{correct}
\rightarrow
\text{repeat}
\rightarrow
\text{distil}.
$$

Distillation asks:

> What compact field representation best preserves what we have learned?

The sleep analogy therefore becomes even stronger.

During active operation, MARL accumulates corrections.

During consolidation, it restructures those corrections into a cleaner representation.

---

# 21. Proposed First Experiment: Recover a Hidden Field

The first experiment should avoid gravitational complexity entirely.

Create a known synthetic scalar potential:

$$
P^*(x,y).
$$

Derive a hidden force field:

$$
V^*
=
-\nabla P^*.
$$

Release particles into this field and generate trajectories.

MARL does **not** receive \(P^*\).

It receives only sparse trajectory observations:

$$
x_i(t).
$$

Initialise a deliberately incorrect MARL potential:

$$
P_0(x,y).
$$

Predict trajectories using:

$$
V=-\nabla P.
$$

Measure trajectory error:

$$
L
=
\sum_{i,t}
\|
x^{obs}_i(t)
-
x^{pred}_i(t)
\|^2.
$$

Backpropagate that error through:

$$
\text{trajectory}
\leftarrow
V
\leftarrow
\nabla P
\leftarrow
\text{MARL}.
$$

Then determine whether MARL reconstructs the hidden potential.

---

# 22. What to Measure

For each iteration measure:

* trajectory RMS error;
* field RMS error against hidden ground truth;
* gradient RMS error;
* kernel count;
* updates per kernel;
* responsibility distribution;
* refinement depth;
* work performed;
* convergence rate.

Most importantly, visualise:

$$
P^*
$$

versus

$$
P_{\text{MARL}}
$$

and separately visualise MARL representational effort.

This gives both conventional accuracy metrics and insight into how the hierarchy discovers the field.

---

# 23. Deliberately Sparse Observations

Once reconstruction works, progressively remove observations.

Test:

* dense trajectories;
* sparse trajectories;
* partial trajectories;
* noisy trajectories;
* observations confined to particular regions;
* moving observation windows.

Ask:

> How much of the hidden continuous field can MARL infer from incomplete evidence?

Also examine where MARL refuses to invent detail.

Ideally, unobserved regions remain coarse or uncertain rather than acquiring unjustified complexity.

---

# 24. Second Experiment: Hidden Perturbation

Once the basic field can be recovered, introduce an unknown local perturbation:

$$
P^*
=
P_{\text{known}}
+
\delta P.
$$

Do not tell MARL about \(\delta P\).

Allow observations to expose its effects.

Then inspect:

* where residual first appears;
* which MARL scales activate;
* whether refinement localises around the perturbation;
* how quickly the reconstructed field converges.

This directly tests whether representational dynamics can reveal hidden physical structure.

---

# 25. Third Experiment: Incorrect Law

Generate observations using:

$$
F_t
=
\mathcal L(F)+\alpha O(F)
$$

but give MARL only

$$
F_t
=
\mathcal L(F).
$$

The system cannot completely eliminate its residual because its assumed law is incomplete.

Observe the residual field:

$$
R(x,t)
=
F_{\text{observed}}(x,t)
-
F_{\text{predicted}}(x,t).
$$

The important question is whether the residual contains **persistent structure** rather than behaving like uncorrelated observational noise.

Measure:

* residual magnitude;
* residual spatial distribution;
* residual direction where applicable;
* persistence through time;
* distribution across MARL scale;
* correlation with known physical quantities;
* representational effort required to repeatedly absorb the discrepancy.

If MARL continually corrects the same kind of error in the same circumstances, that is evidence that the forward model is systematically incomplete.

The MARL correction itself can therefore be treated as an empirical missing-dynamics field:

$$
C(x,t)
\approx
F_{\text{corrected}}(x,t)
-
F_{\text{predicted}}(x,t).
$$

Over a sufficiently small timestep,

$$
\frac{C(x,t)}{\Delta t}
$$

provides an estimate of the missing contribution to the evolution law.

Thus the observational system does more than report:

> **The model is wrong here.**

It begins to estimate:

> **This is approximately the field contribution required to make the model right here.**

---

# 26. Residual Accumulation as Evidence

A single discrepancy may be noise.

Repeated discrepancies with common structure are much more interesting.

Maintain an accumulated residual MARL:

$$
M_R(x,s,t)
$$

representing systematic unexplained dynamics across position, scale and potentially state.

Rather than simply applying each correction and forgetting it, preserve information about the correction:

$$
R_t
=
O_t-P_t.
$$

Then analyse whether residuals cluster according to:

* position;
* scale;
* field value;
* gradient;
* curvature;
* velocity;
* neighbouring fields;
* temporal phase;
* other state variables.

This turns correction history into a dataset for discovering what the assumed dynamics fail to explain.

A persistent relationship such as

$$
R
\propto
\nabla^2F
$$

might suggest a missing diffusion term.

A relationship such as

$$
R
\propto
V\cdot\nabla F
$$

might suggest missing or incorrectly parameterised transport.

The MARL algebra therefore supplies not only the simulation operators but a **candidate vocabulary for explaining residual structure**.

---

# 27. Fourth Experiment: Candidate Operator Recovery

Once structured residuals can be detected, introduce a small library of candidate operators:

$$
O_1(F),O_2(F),\ldots,O_n(F).
$$

For example:

$$
O_1(F)=\nabla F
$$

$$
O_2(F)=\nabla^2F
$$

$$
O_3(F)=V\cdot\nabla F
$$

$$
O_4(F)=F
$$

$$
O_5(F)=F^2.
$$

Construct a candidate correction:

$$
C(F)
=
\sum_i\theta_iO_i(F).
$$

Then fit:

$$
F_t
=
\mathcal L(F)
+
\sum_i\theta_iO_i(F)
$$

against observations.

If the synthetic ground truth contains, for example,

$$
F_t
=
\mathcal L(F)
+
D\nabla^2F,
$$

the experiment succeeds if optimisation drives the Laplacian coefficient toward

$$
\theta_{\nabla^2}\approx D
$$

while irrelevant operator coefficients approach zero.

This is a deliberately constrained form of equation discovery.

It asks whether the MARL algebra can recover a missing physical term when that term already exists within its operator vocabulary.

---

# 28. Fifth Experiment: Unknown Parameter

Before attempting arbitrary law discovery, test the easier problem of an incorrect parameter.

Generate ground truth using

$$
F_t
=
-V\cdot\nabla F
+
D^*\nabla^2F.
$$

Give the model an incorrect value

$$
D_0\ne D^*.
$$

Allow observations to optimise \(D\):

$$
D_{n+1}
=
D_n
-
\eta
\frac{\partial L}{\partial D}.
$$

Success means recovering

$$
D\rightarrow D^*.
$$

Repeat for parameters such as:

* diffusion;
* viscosity;
* damping;
* force strength;
* source intensity;
* mass;
* drag.

This establishes the complete differentiable path:

$$
\boxed{
\text{observation}
\rightarrow
\text{loss}
\rightarrow
\text{operator graph}
\rightarrow
\text{physical parameter}
}
$$

before attempting structural changes to the law itself.

---

# 29. From State Estimation to System Identification

These experiments form a useful progression.

### Level 1 — State inference

Assume the law and parameters are correct.

Learn:

$$
M.
$$

Question:

> What field state best explains the observations?

### Level 2 — Parameter inference

Assume the law is correct but its parameters may not be.

Learn:

$$
M,\theta.
$$

Question:

> What field and parameter values best explain the observations?

### Level 3 — Operator inference

Assume the law may be incomplete.

Learn:

$$
M,\theta,\{O_i\}.
$$

Question:

> Which combination of available field operators best explains the observations?

### Level 4 — Structural discovery

Allow genuinely new operator structures to be proposed.

Question:

> What evolution law best explains the observed world?

Each level should be demonstrated independently before proceeding to the next.

---

# 30. Three-Body Demonstrator

Only after the synthetic experiments work should the three-body problem return.

The objective is **not** to solve the three-body problem analytically.

Instead, use it as a demanding test of observational field inference and representational interpretability.

Construct a known synthetic three-body system.

Generate observations of body positions:

$$
x_1(t),x_2(t),x_3(t).
$$

Then deliberately hide or perturb some combination of:

* initial positions;
* initial velocities;
* masses;
* gravitational field;
* an additional perturbing force.

Allow MARL to predict forward and assimilate observations.

Measure conventional trajectory error, but simultaneously inspect the internal representational dynamics.

---

# 31. The Representation as an Instrument

For the three-body experiment, record:

$$
E(x,s,t)
$$

residual,

$$
R(x,s,t)
$$

responsibility,

$$
K(x,s,t)
$$

kernel density,

and events such as:

* refinement;
* kernel creation;
* responsibility migration;
* rapid coefficient change;
* distillation.

Then compare these against physical events:

* close approaches;
* rapid acceleration;
* trajectory divergence;
* exchange of energy;
* transitions between temporary orbital configurations.

The central question becomes:

> Does MARL's internal representational behaviour reveal impending dynamical complexity before it becomes obvious in the macroscopic trajectories?

If so, the adaptive representation has become an **endogenous complexity sensor**.

---

# 32. Observation-Driven Field Moments

Because the field is continuous and differentiable, observations can constrain not merely field values but field moments.

For example, an observed trajectory constrains acceleration:

$$
a
=
\frac{d^2x}{dt^2}.
$$

Acceleration constrains the local field:

$$
a
=
-\nabla P.
$$

Multiple trajectories crossing related regions constrain the spatial variation of that field.

Accumulated evidence therefore constrains:

$$
P,
\qquad
\nabla P,
\qquad
\nabla^2P,
\qquad
\ldots
$$

at different positions and scales.

MARL's hierarchy provides a natural place for these constraints to accumulate.

This is the important distinction from simply fitting motion vectors.

The objective is not merely:

> Predict where the object moves next.

It is:

> Infer the continuous field whose local moments explain why all observed objects move as they do.

---

# 33. Uncertainty and Identifiability

Observation alone does not guarantee that the underlying field can be uniquely reconstructed.

Different fields or parameter combinations may produce observations that are indistinguishable over the available measurement window.

Therefore MARL should eventually distinguish:

$$
\text{poorly represented}
$$

from

$$
\text{poorly observed}.
$$

These are fundamentally different.

A region may have low residual simply because no observation constrains it.

Representational confidence should therefore incorporate observational support.

Conceptually define:

$$
C_{\text{obs}}(x,s,t)
$$

as evidence coverage or confidence.

Then a field visualisation can distinguish:

* high-confidence / low-error;
* high-confidence / high-error;
* low-confidence / apparently low-error;
* unconstrained regions.

This becomes especially important when using MARL for scientific inference.

The system should not confuse **absence of contradiction** with **evidence of correctness**.

---

# 34. Observation as Active Sampling

Once observational confidence exists, the model can potentially ask where another measurement would be most informative.

Candidate locations could be scored according to:

$$
I(x)
=
f(
\text{uncertainty},
\text{residual},
\text{model disagreement},
\text{expected information gain}
).
$$

The system could then request or direct observations toward regions where they best discriminate between competing field explanations.

For simulation this may mean choosing additional synthetic probes.

For robotics it could mean directing a sensor.

For scientific instrumentation it could suggest where the next measurement is valuable.

The loop becomes:

$$
\boxed{
\text{model}
\rightarrow
\text{predict}
\rightarrow
\text{identify uncertainty}
\rightarrow
\text{observe}
\rightarrow
\text{learn}
}
$$

MARL therefore becomes not only observational but potentially **experiment-seeking**.

---

# 35. Relationship to the Lazy Expression Graph

The lazy expression graph is central to this architecture.

For forward execution it provides:

* operator fusion;
* derivative reuse;
* sparse traversal;
* adaptive execution;
* GPU compilation.

For inverse execution it provides:

* dependency tracking;
* automatic differentiation;
* parameter gradients;
* state gradients;
* attribution of observational residuals.

The same graph therefore serves as both:

$$
\boxed{\text{field compiler}}
$$

and

$$
\boxed{\text{inference graph}}.
$$

This strongly argues against implementing MARL algebra merely as a collection of eager numerical functions.

The graph itself is valuable information.

---

# 36. A Possible Computational Architecture

Conceptually:

```text
                OBSERVATIONS
                     │
                     ▼
              Observation H
                     │
                     ▼
                  Loss
                     │
              backward pass
                     │
                     ▼
 ┌───────────────────────────────────┐
 │       MARL EXPRESSION GRAPH       │
 │                                   │
 │ Field → Gradient → Dynamics → ... │
 │                                   │
 └───────────────────────────────────┘
          │                  ▲
       forward            gradients
          │                  │
          ▼                  │
       PREDICTION            │
                             │
                     MARL parameters
```

Forward execution predicts reality.

Backward execution determines what must change to explain reality better.

Responsibility determines where those changes should be absorbed.

Distillation periodically consolidates what has been learned.

---

# 37. The Larger Hypothesis

MARL began as an adaptive representation:

$$
\text{data}
\rightarrow
\text{continuous field}.
$$

Field Algebra extends it into computation:

$$
\text{continuous fields}
\rightarrow
\text{continuous dynamics}.
$$

Observational Dynamics extends it again:

$$
\text{observations}
\rightarrow
\text{field correction}.
$$

Together:

$$
\boxed{
\text{represent}
\rightarrow
\text{predict}
\rightarrow
\text{observe}
\rightarrow
\text{correct}
\rightarrow
\text{consolidate}
}
$$

The resulting system is neither simply a neural network nor simply a numerical solver.

It is an adaptive continuous model whose internal representation, computation and learning occur in the same field space.

---

# 38. Core Research Question

The strongest version of the hypothesis is not:

> Can MARL predict a dynamical system?

Many methods can.

Nor is it:

> Can MARL fit observations?

Many methods can do that too.

The more interesting question is:

> **Can an adaptive, hierarchical, analytic field representation expose how much explanatory structure reality requires, where that structure is required, and at what scale?**

If so, MARL's changing internal representation becomes part of the scientific output.

The system would provide not merely a prediction, but an inspectable account of **where its explanation of the world is simple, where it becomes complicated, and where observation says that explanation is wrong**.

That is considerably more interesting than merely producing another trajectory.
