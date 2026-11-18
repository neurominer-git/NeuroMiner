# NeuroMiner 2 Results Viewer: connectivity viewspace methods

**Methodological note for the NM2 Results Viewer**  
**Implementation basis:** pre-hackathon NM2 codebase supplied on 2026-09-06 (`NM_4.9995`)  
**Scope:** connectivity matrix, 2-D topology/grouped-ring network, 3-D glass-brain representation, graph sparsification, node/edge tuning, grouping, anatomy and lighting.

---

## 1. Purpose and conceptual position

The NM2 connectivity viewspace is designed for feature spaces in which each model feature already represents a **connection between two retained nodes/ROIs**.

This is closely related to the Results Viewer relational-analysis tools, but the starting point is different:

```text
Relational analysis of tabular-like features
--------------------------------------------
ordinary features
      |
feature-by-feature relation matrix
      |
graph is constructed from relations among features


Connectivity viewspace
----------------------
ROIs / nodes + predefined connectivity edges
      |
each model feature already corresponds to one edge
      |
the selected Results Viewer feature statistic is mapped
onto the pre-existing connectivity graph
```

This distinction is essential.

In the connectivity viewspace, NM2 does **not** infer which pairs of ROIs are connected. The retained node identities, edge identities, edge order, directed/undirected status and node coordinates are established by DataIO and persisted in the connectivity descriptor. The Results Viewer maps the selected model-feature statistic back onto that fixed edge space.

Consequently:

> **The connectivity graph is a representation of model-result values defined on an already established connectivity topology. It is not a graph inferred from a new correlation analysis performed in the Results Viewer.**

The three principal connectivity representations are:

1. **ROI-by-ROI matrix**;
2. **2-D node-link network**, with topology or grouped-ring layout;
3. **3-D glass-brain network**, using retained MNI/world coordinates.

All three use the same persisted edge identities and the same selected Results Viewer measure.

---

## 2. Authoritative connectivity data

For one connectivity modality, the Results Viewer consumes the persisted DataIO connectivity descriptor, including:

- retained node identities;
- retained node labels;
- retained node coordinates;
- coordinate source, space and units;
- retained edge index;
- edge names;
- matrix type: directed or undirected;
- triangle/vectorization convention;
- diagonal inclusion convention.

The Results Viewer also obtains the selected feature-value vector through the shared Model Feature Inspection resolver.

There is an exact positional identity:

\[
\text{feature position}=\text{persisted connectivity edge position}.
\]

If the persisted descriptor contains \(E\) edges, the selected Results Viewer vector must contain exactly \(E\) feature values. A mismatch is treated as a provenance-integrity error. The viewer does not guess, remap or reconstruct a different edge space.

---

## 3. The selected edge value

Let

\[
w_e
\]

denote the selected Results Viewer feature statistic for connectivity edge \(e\).

The scientific meaning of \(w_e\) depends on the selected Results Viewer measure. It could, for example, be a model-derived feature statistic. The connectivity renderer does **not** automatically reinterpret it as a raw connectivity coefficient or Pearson correlation.

This point is important because the same graph machinery is used for multiple Results Viewer measures.

> **Graph topology comes from DataIO. Edge weights shown in the viewspace come from the currently selected Results Viewer measure.**

---

# Part I — Shared display filtering

## 4. Display thresholding occurs before graph sparsification

Before the 2-D or 3-D graph is constructed, every persisted edge value is passed through the same canonical Results Viewer display-semantics machinery used by imaging representations.

An edge is eligible for network rendering only if:

- its value is finite/non-missing;
- the canonical display-threshold contract classifies it as included;
- its value is non-zero.

Thus the graph construction sequence is:

```text
Persisted connectivity edges
        |
        v
Selected Results Viewer measure
        |
        v
Canonical display threshold
        |
        +--> missing values removed
        +--> subthreshold values removed
        +--> exact zeros removed
        |
        v
Threshold-eligible non-zero edge universe
        |
        v
Graph sparsification
```

The user therefore has **two conceptually separate filters**:

1. the shared Results Viewer feature threshold;
2. the graph-specific sparsification rule.

Changing the colour scale alone does not change graph membership. Changing the feature threshold can change the eligible edge universe and therefore can change the graph.

---

## 5. Shared colour, range and opacity controls

The connectivity matrix, 2-D network and 3-D glass brain share the canonical Results Viewer display state.

The user can tune:

- feature threshold;
- colour gradient;
- display range;
- feature opacity.

Available display-range modes include:

- robust polarity-wise scaling;
- full finite data range;
- symmetric absolute scaling;
- manual range.

These settings are presentation/display-semantic controls. They do not redefine DataIO edge identity.

For the network views, edge colour is resolved directly from the selected edge value \(w_e\) through the shared colour mapping. Thus positive and negative values can retain their polarity-specific colour semantics while graph sparsification can still operate on \(|w_e|\).

---

# Part II — Connectivity matrix

## 6. ROI-by-ROI matrix

The matrix view reconstructs the persisted edge vector into an \(N\times N\) node matrix using the stored `edgeIndex`.

For each persisted edge \(e=(i,j)\),

\[
M_{ij}=w_e.
\]

For an undirected connectivity definition, the corresponding mirrored matrix element is also populated. For a directed definition, source and target orientation are retained.

The axes are:

- **rows:** source ROI;
- **columns:** target ROI.

The viewer separately tracks:

- cells corresponding to retained edges;
- missing values;
- exact zero values;
- diagonal cells.

The matrix does not create additional edges. It is a square representation of the same persisted vectorized edge space used by the network views.

### Matrix tuning

The matrix supports:

- shared threshold/colour/display-range/opacity controls;
- zoom from \(1\times\) to \(8\times\);
- exact node labels;
- exact edge selection and cross-view identity.

The matrix is particularly useful when the goal is precise pairwise inspection rather than graph topology.

---

# Part III — 2-D connectivity network

## 7. Graph sparsification

A dense connectivity edge set can become visually unreadable. NM2 therefore constructs a sparse displayed graph from the threshold-eligible non-zero edges.

All graph-sparsification rules are based on

\[
|w_e|.
\]

Three modes are available.

### 7.1 Strongest per node

This is the default mode.

For each node, NM2 retains the \(K\) incident edges with the largest absolute magnitude.

Default:

\[
K=3.
\]

For undirected graphs, all incident edges are considered together.

For directed graphs, NM2 independently retains:

- the \(K\) strongest outgoing edges;
- the \(K\) strongest incoming edges.

The union of these selections is retained.

A global maximum edge count is then applied.

Default:

\[
E_{\max}=500.
\]

This mode is useful when the goal is to preserve some local representation of every node rather than allowing a few globally dominant regions to consume the entire edge budget.

### 7.2 Fixed density

Eligible edges are ranked by \(|w_e|\), and the strongest fraction is retained.

If the requested density is \(\rho\),

\[
E_{\text{display}}
=
\left\lceil
\rho E_{\text{eligible}}
\right\rceil ,
\]

for \(\rho>0\).

Default:

\[
\rho=0.03.
\]

Thus the default fixed-density setting retains approximately the strongest 3% of threshold-eligible non-zero edges.

### 7.3 Absolute cutoff

An edge is retained when

\[
|w_e|\ge c,
\]

where \(c\) is the user-specified absolute cutoff.

This cutoff is expressed in the units of the currently selected Results Viewer measure.

It should therefore not be interpreted as a correlation threshold unless the selected measure itself is a correlation coefficient.

### 7.4 Selected-edge pinning

If the user has explicitly selected a persisted edge in another connectivity representation, NM2 can keep that exact edge visible even if it would otherwise fall outside the current sparsification result.

This preserves cross-view selection identity. It means that a selected graph may temporarily contain one explicitly pinned edge in addition to the ordinary sparsification result.

---

## 8. 2-D topology layout

The **Topology** layout is a deterministic force-directed layout. Node positions in this view are abstract graph coordinates, not anatomical coordinates.

A schematic example:

```text
       A
      / \
     B---C
      \ /
       D
```

The purpose is to place strongly connected nodes near one another while separating unrelated nodes.

### 8.1 Initialization

Nodes are first placed uniformly around a circle using stable node order.

### 8.2 Repulsion

Every node pair exerts a repulsive force approximately proportional to

\[
F_{\mathrm{repel}}\propto \frac{k^2}{d},
\]

where \(d\) is the current 2-D distance and \(k\) is the layout's ideal separation scale.

### 8.3 Edge attraction

Retained edges exert attraction. The attraction increases with:

- current geometric separation;
- absolute edge magnitude.

The implementation scales the attraction by

\[
0.70+0.60\frac{|w_e|}{\max |w|}.
\]

Thus a stronger displayed connection exerts more layout attraction than a weaker one.

### 8.4 Stabilization

A weak attraction toward the plot centre prevents global drift. The displacement temperature is progressively reduced during the iterations.

The number of layout iterations decreases for very large graphs to keep the representation interactive.

### 8.5 Final normalization

The resulting layout is normalized to a bounded \([0,1]\times[0,1]\) plotting coordinate system with margins.

Therefore:

> **The topology view expresses graph structure, not MNI anatomy. Distances on screen are layout distances and must not be interpreted as physical brain distances.**

---

## 9. 2-D grouped-ring layout

The **Grouped ring** layout represents nodes on a circle, with nodes belonging to the same group placed in contiguous angular sectors.

```text
                Group A
           A1  A2  A3  A4
        /                 \
   Group D                 Group B
     D1                      B1
     D2                      B2
        \                  /
           C1  C2  C3
                Group C
```

The ring is useful when the scientific emphasis is on:

- anatomical/network categories;
- spatial groupings;
- between-group and within-group connectivity.

### 9.1 Available group definitions

Grouping can be based on:

1. **No grouping**;
2. eligible categorical columns from the persisted connectivity node metadata;
3. deterministic **MNI spatial clusters**, when every retained node has finite coordinates.

Identifier, label and coordinate columns are excluded from metadata grouping. A metadata field is exposed only when it defines a genuine categorical partition rather than a unique value for every node.

### 9.2 MNI spatial grouping

When MNI spatial clustering is selected, NM2 performs deterministic \(k\)-means-like grouping in the three-dimensional coordinate space.

The requested number of spatial groups is constrained to:

\[
2\le K\le20,
\]

with default

\[
K=7.
\]

Initialization and tie resolution are deterministic. Cluster labels are ordered by their spatial centres and exposed as `MNI cluster 1`, `MNI cluster 2`, etc.

These groups are a **display grouping**, not an independently validated anatomical parcellation.

### 9.3 Within-group ordering

Within each group, nodes are seriated using a deterministic nearest-neighbour path based on their stored 3-D coordinates where available.

This keeps spatially nearby nodes relatively close around the ring.

### 9.4 Group sectors

Each group receives one contiguous ring arc. Small gaps are inserted between groups.

The group sectors are colour coded using a fixed categorical palette.

### 9.5 Edge routing

In topology mode, edges are drawn as straight lines.

In grouped-ring mode, edges are drawn as quadratic curves that are attracted toward the current ring centre. The control point is shifted 62% of the way from the edge midpoint toward the ring centre.

This produces a centre-bundled appearance:

```text
node o \         / o node
        \       /
         \     /
          \   /
           \ /
            •   approximate bundle attractor
           / \
          /   \
node o --     -- o node
```

The bundling is purely a presentation geometry. It does not alter edge identity, edge value, graph statistics or sparsification.

---

# Part IV — Node tuning in the 2-D and 3-D network

## 10. Node-size metric

The user can map node size to a graph-derived metric computed from the current sparsified displayed-result graph.

Available metrics include:

- degree;
- absolute strength;
- positive strength;
- negative strength;
- weighted betweenness centrality;
- harmonic closeness;
- eigenvector centrality.

Directed graphs additionally expose:

- in-degree;
- out-degree;
- in-strength;
- out-strength.

The default node-size metric is:

\[
\text{absolute strength}
=
\sum_j |w_{ij}|.
\]

These quantities describe the **currently retained displayed graph**, not the complete original connectivity matrix.

They are not predictive feature-importance measures.

---

## 11. Relative versus absolute node scaling

Let \(m_i\ge0\) be the selected node-size metric.

### 11.1 Relative scaling

Relative scaling normalizes node size by the largest node metric in the displayed graph.

With

\[
u_i=\frac{m_i}{\max_j m_j},
\]

NM2 applies a square-root scaling so that large nodes do not dominate excessively.

The implemented radius-scale factor is equivalent to

\[
s_i=
\operatorname{clip}
\left(
0.55+
1.65\,f\sqrt{u_i},
\ 0.5,\ 8
\right),
\]

where \(f\) is the user-controlled node scale factor.

Default:

\[
f=1.
\]

Relative scaling answers:

> **How large is this node compared with the strongest node in the current graph?**

### 11.2 Absolute scaling

In absolute mode,

\[
s_i=
\operatorname{clip}
\left(
0.55+
f\sqrt{m_i},
\ 0.5,\ 8
\right).
\]

This preserves differences in the absolute numerical scale of the selected node metric.

Absolute scaling is therefore more sensitive to the units and magnitude of the chosen metric.

---

## 12. Density-aware 2-D node size

The final 2-D circle radius combines:

1. the graph's density-aware base node size;
2. the node-specific scale \(s_i\).

The base size becomes smaller as the number of nodes and edges increases. This prevents dense networks from becoming dominated by overlapping circles.

Schematically:

\[
R_i^{2D}=R_{\mathrm{base}}(N,E)\,s_i.
\]

Thus node scaling is adaptive at two levels:

- global adaptation to graph complexity;
- local adaptation to the chosen node metric.

---

# Part V — Edge tuning

## 13. Edge colour

Edge colour is determined from the signed value \(w_e\) through the shared Results Viewer colour contract.

The colour mapping therefore retains the semantics of the selected feature measure.

Colour tuning and display-range tuning do **not** alter graph sparsification.

---

## 14. Edge opacity

Before the global feature-opacity control is applied, retained edge opacity increases smoothly with absolute edge magnitude.

Let

\[
u_e=\frac{|w_e|}{\max |w|}.
\]

The implemented magnitude-dependent factor is

\[
\alpha_e^{*}
=
0.16+0.76\sqrt{u_e}.
\]

The final graph opacity is then multiplied by the shared feature opacity.

Thus stronger displayed connections are visually more opaque while weaker retained connections remain visible.

---

## 15. Edge-width scaling

Edge-width scaling can be switched on or off.

When enabled, NM2 does not scale widths directly between the raw minimum and maximum, because a single extreme edge could collapse most widths into a narrow visual range.

Instead, the selected edge magnitudes are summarized using approximately the 10th and 90th percentiles:

\[
q_{0.10},\ q_{0.90}.
\]

For edge magnitude \(a_e=|w_e|\),

\[
v_e=
\operatorname{clip}
\left(
\frac{a_e-q_{0.10}}
{q_{0.90}-q_{0.10}},
0,1
\right),
\]

and the presentation width is

\[
W_e=0.45+4.35\sqrt{v_e}.
\]

The square-root transform compresses the high end and gives weaker retained edges more visible differentiation.

When edge-width scaling is disabled, all edges use the graph's density-aware base width.

Importantly:

> **Edge-width scaling is presentation-only. It does not change edge selection or graph statistics.**

---

# Part VI — 3-D glass-brain representation

## 16. Scientific coordinate requirement

The 3-D glass-brain view is enabled only if every retained node has finite stored coordinates.

The Results Viewer does not invent coordinates for missing nodes.

For the ordinary NM2 connectivity workflow these are MNI/world coordinates in millimetres. The connectivity adapter carries the persisted coordinate source, coordinate space and units forward into the representation.

The 3-D scene therefore differs fundamentally from the 2-D topology layout:

```text
2-D topology
------------
position = graph-layout coordinate
meaning  = topological organization

3-D glass brain
---------------
position = persisted node world/MNI coordinate
meaning  = anatomical location
```

The **same sparsified graph scene** is projected into these anatomical coordinates. Graph content is not recomputed specifically for 3-D.

---

## 17. 3-D node objects

Every retained node is rendered as a sphere centred at its persisted \((x,y,z)\) coordinate.

The sphere uses:

- 8 latitude bands;
- 12 longitude bands.

Its base radius is

\[
R_i^{3D}=2.8\,s_i,
\]

in the scene's world-coordinate units.

Because the normal connectivity coordinate system is millimetres, this corresponds operationally to a millimetre-scale sphere radius.

The same \(s_i\) is derived from the selected node-size metric and relative/absolute scaling described above.

A selected node is enlarged by an additional factor:

\[
1.45.
\]

Node colour is based on the selected node grouping. With no grouping, a neutral slate colour is used. Group colours are shared with the 2-D network.

The 3-D node colour is slightly lightened before rendering to preserve visibility under lighting.

---

## 18. 3-D edge objects

Every displayed graph edge is rendered as a tube connecting the two node coordinates.

The tube uses a six-sided cross-section.

Its radius is derived from the same edge-width presentation value used by the 2-D graph:

\[
R_e^{3D}
=
\operatorname{clip}
\left(
0.18+0.22W_e,
0.25,
1.35
\right).
\]

A selected edge is enlarged by an additional factor:

\[
1.7.
\]

Thus 2-D and 3-D thickness are not independently tuned. They are two geometric projections of one shared edge-width state.

For directed connectivity, NM2 adds an arrowhead at the target end of the tube.

The arrowhead is a six-sided cone-like primitive whose base radius is approximately \(2.2R_e^{3D}\).

---

## 19. Shared graph tuning between 2-D and 3-D

The 2-D network and 3-D glass brain use the same controls for:

- node grouping;
- graph sparsification;
- node-size metric;
- relative/absolute node scaling;
- node scale factor;
- edge-width scaling.

Therefore, switching from 2-D to 3-D does not create a second network.

It changes the **geometric coordinate system**:

```text
same nodes
same retained edges
same edge values
same threshold
same sparsification
same node metric
same node-size scaling
same edge-width scaling
        |
        +--> 2-D: topology / grouped-ring coordinates
        |
        +--> 3-D: persisted MNI/world coordinates
```

This cross-view identity is a central methodological property of the connectivity viewspace.

---

# Part VII — Structural anatomy in the glass brain

## 20. Structural template

The glass-brain scene is displayed against an anatomical envelope derived from the selected shared NM structural template.

The backend:

1. loads the selected structural volume;
2. identifies finite non-zero anatomical support;
3. generates a surface mesh through the shared NM imaging mesh service;
4. caches/materializes that mesh for browser rendering.

The connectivity graph does not alter the anatomical mesh.

Changing the structural template is therefore a **display-reference change**, not a change to node or edge values.

---

## 21. Anatomy appearance

The glass-brain connectivity view exposes:

- anatomy opacity;
- anatomy brightness.

Defaults are approximately:

\[
\text{opacity}=0.18,
\qquad
\text{brightness}=1.
\]

The low default opacity is deliberate: the anatomy provides spatial context while allowing internal connectivity nodes and tubes to remain visible.

These controls do not change graph values, graph statistics, coordinates or edge selection.

---

# Part VIII — Lighting and 3-D appearance

## 22. Lighting model

The glass-brain view uses the shared NM2 3-D lighting controls.

The adjustable parameters are:

- lighting reference frame;
- light azimuth;
- light elevation;
- colour temperature;
- ambient term;
- diffuse term;
- specular term;
- shininess;
- background colour.

Default normalized settings are:

| Parameter | Default |
|---|---:|
| lighting frame | camera |
| azimuth | \(35^\circ\) |
| elevation | \(25^\circ\) |
| colour temperature | neutral |
| ambient | 0.22 |
| diffuse | 0.75 |
| specular | 0.10 |
| shininess | 24 |
| background | white |

The lighting frame can either:

- follow the camera;
- remain fixed to the anatomy/world.

### What lighting affects

The structural mesh and spherical nodes participate in the lit 3-D rendering.

Connectivity edge tubes are deliberately rendered without surface lighting so that their assigned feature colours remain legible and stable against changes in light direction.

Thus lighting is a 3-D presentation control and does not alter the scientific edge-value encoding.

---

# Part IX — Camera, selection and interaction

## 23. Camera

When first opened, the glass brain:

1. fits the full anatomical scene;
2. adopts a right-side preset.

The user can then rotate/orbit, zoom and inspect the scene using the shared 3-D interaction system.

Standard anatomical presets include:

- anterior;
- posterior;
- left;
- right;
- superior;
- inferior.

Fit/reset returns the scene to a fitted right-side view.

The camera state changes presentation only.

---

## 24. Hover and selection

Node and edge identity is preserved between:

- matrix;
- 2-D network;
- 3-D glass brain.

Hovering or selecting an object exposes the exact persisted node/edge identity.

The 3-D pointer interaction first tests projected node positions and then the projected edge segments.

Selected objects are emphasized geometrically:

- node radius × 1.45;
- edge radius × 1.7;
- selected objects use a warm highlight colour.

Selection emphasis does not modify underlying values.

---

# Part X — Labels and node grouping

## 25. 2-D label management

The 2-D network supports:

- automatic labels;
- no labels;
- top-\(N\) labels;
- all labels.

Default:

- label mode: **Auto**;
- top-\(N\) count when used: **24**.

The graph label planner adapts label placement to available space and network size.

In topology mode, labels can be displaced with leader lines to reduce overlap.

In grouped-ring mode, labels are placed radially and rotated around the ring.

A temporary **Label zoom** option can enlarge labels on hover.

Labeling is presentation-only.

---

# Part XI — Relation to graph statistics

## 26. Graph statistics in the connectivity viewspace

After sparsification, NM2 computes node statistics from the **retained displayed-result graph**.

These include the same graph-theoretical quantities discussed in the relational-analysis methods note:

- degree;
- absolute/positive/negative strength;
- weighted betweenness centrality;
- harmonic closeness;
- eigenvector centrality;
- directed in/out metrics where applicable.

For shortest-path statistics, an edge with absolute magnitude \(|w_e|\) has path length

\[
\ell_e=\frac{1}{|w_e|+10^{-12}}.
\]

Hence larger absolute displayed-result values correspond to shorter graph paths.

However, the scientific interpretation differs from the tabular relation graph.

In the connectivity viewspace, \(w_e\) is the **currently selected model-feature result value on a predefined connectivity edge**. It is not necessarily a correlation coefficient.

Therefore:

> **Connectivity centrality describes topology after weighting and sparsifying the selected model-result connectivity map. It should not automatically be interpreted as centrality of the original raw biological connectivity matrix.**

These graph statistics are used internally for node scaling/inspection. They are not a dedicated exported graph-statistics result product.

---

# Part XII — How the connectivity graph differs from relational feature graphs

## 27. Side-by-side comparison

| Property | Tabular relational analysis | Connectivity viewspace |
|---|---|---|
| Nodes | ordinary model features | predefined ROIs/nodes |
| Candidate edges | pairwise feature relations | persisted DataIO connectivity edges |
| Primary edge value | stored feature-feature relation layer | selected Results Viewer feature statistic |
| Graph topology | constructed from relation matrix | established by DataIO |
| 2-D coordinates | graph layout | graph layout / grouped ring |
| 3-D coordinates | not intrinsic to generic tabular features | persisted MNI/world coordinates |
| Sparsification | relation-graph selection | connectivity edge selection |
| Edge patterns | hierarchical link communities available | not a separate relation-pattern analysis in this viewspace |
| Node centrality | property of sparsified relation graph | property of sparsified displayed-result connectivity graph |

The same generic node-link renderer is reused where appropriate, but the **scientific authority for the edge universe is different**.

---

# Part XIII — Recommended tuning strategy

## 28. A practical sequence for participants

For exploratory visualization, a defensible order is:

1. **Choose the scientific Results Viewer measure first.**  
   This determines what the edge values mean.

2. **Set the shared feature threshold.**  
   This defines which non-zero edges are eligible before graph sparsification.

3. **Choose a sparsification strategy.**
   - Strongest per node: good for preserving local representation across ROIs.
   - Fixed density: good for comparing graphs at a common visual density.
   - Absolute cutoff: useful when the measure has an interpretable absolute scale.

4. **Inspect the 2-D topology view.**  
   This emphasizes emergent graph organization.

5. **Inspect grouped ring when meaningful node metadata are available.**  
   This emphasizes within-group and between-group connections.

6. **Choose the node-size metric.**  
   Absolute strength is the default and is usually the easiest to explain.

7. **Use relative node scaling for exploratory comparison within one graph.**  
   Use absolute scaling only when the magnitude of the selected node metric itself is scientifically meaningful across the compared views.

8. **Use the 3-D glass brain for anatomical localization.**  
   Keep in mind that graph selection is unchanged; only coordinates are anatomical.

9. **Tune anatomy opacity and lighting last.**  
   These are presentation controls and should not drive scientific edge selection.

---

# Part XIV — Important interpretation cautions

## 29. What should not be inferred

### 29.1 A large node is not automatically an important predictor

Node size reflects the selected graph metric in the sparsified displayed-result network.

It is not automatically:

- model feature importance;
- causal influence;
- statistical significance;
- biological importance.

### 29.2 A thick edge is not automatically a raw strong connection

Thickness reflects the absolute magnitude of the selected Results Viewer measure.

If the selected measure is not raw connectivity, a thick edge should not be described as high raw functional/structural connectivity.

### 29.3 2-D topology distance is not anatomical distance

Only the glass-brain coordinates have anatomical/world-coordinate meaning.

### 29.4 MNI spatial groups are display-derived groups

The optional MNI clusters are deterministic spatial groups used for display organization. They are not a replacement for an anatomical atlas or a data-driven biological network model.

### 29.5 Sparsification materially changes graph topology

Node centrality, connectedness and apparent network organization depend on the retained edge universe.

The scientific interpretation must therefore state the threshold and sparsification settings used.

---

# Part XV — Short explanation for the hackathon

## 30. 60-second explanation

> **In the connectivity viewspace, every model feature is already a predefined connection between two ROIs. DataIO determines the node and edge identities; the Results Viewer does not infer a new connectivity topology. We map the selected model-result statistic onto those edges, apply the common Results Viewer threshold, and then sparsify the remaining graph using either the strongest edges per node, a fixed density, or an absolute cutoff. The 2-D topology view uses a force-directed layout, whereas the grouped-ring view arranges predefined or MNI-derived node groups around a circle. The 3-D glass brain uses exactly the same retained graph but places the nodes at their persisted MNI coordinates. Node size can encode graph metrics such as strength or centrality, and edge colour, opacity and width encode the selected edge statistic. Anatomy, lighting, camera and labels are presentation controls; they do not change the underlying graph.**

---

# Part XVI — Methods text for reports or publications

## 31. Compact methods paragraph

> Connectivity features were visualized in the NeuroMiner 2 Results Viewer using the persisted DataIO node/edge topology. The selected model-feature statistic was mapped to the corresponding retained connectivity edges using exact persisted feature-to-edge identity. Missing, zero and display-threshold-ineligible edges were excluded before graph sparsification. The displayed graph was sparsified using a user-defined strongest-per-node, fixed-density or absolute-magnitude criterion. Two-dimensional representations used either a deterministic force-directed topology layout or a grouped-ring layout based on persisted categorical node metadata or deterministic MNI-coordinate grouping. The three-dimensional glass-brain representation used the same sparsified graph and mapped retained nodes to their persisted world/MNI coordinates. Node size could be scaled by retained-graph degree, strength or centrality measures, while edge colour reflected the signed selected feature statistic and optional edge width reflected its absolute magnitude. Structural anatomy, lighting, camera, labels and opacity affected presentation only.

## 32. More explicit methods paragraph

> NeuroMiner 2 connectivity visualization treated the DataIO connectivity descriptor as the authority for retained node identities, node coordinates, edge identities and directed/undirected topology. For each selected Results Viewer measure, feature position was required to correspond exactly to persisted edge position. Edge values were first classified by the canonical Results Viewer threshold semantics; missing, zero and subthreshold edges were excluded. The remaining edge universe was sparsified either by retaining the strongest absolute-value edges per node, by retaining a fixed proportion of the globally strongest eligible edges, or by an absolute-value cutoff. Graph node statistics were calculated on this retained displayed-result graph using absolute edge magnitude as affinity; weighted shortest-path length was defined as \(1/(|w|+10^{-12})\). The 2-D topology representation used a deterministic force-directed layout, while grouped-ring visualization placed categorical or deterministic MNI-spatial node groups into contiguous circular sectors. The 3-D glass-brain representation reused the same graph state but substituted persisted MNI/world coordinates for the 2-D layout coordinates. Node sphere size followed the selected graph metric and node-scaling mode, whereas edge tube thickness followed an optional robust magnitude scaling based on the 10th–90th percentile range of retained absolute edge values. Display-range, colour, anatomy, lighting, camera and label controls did not change persisted connectivity identity.

---

## 33. One-line memory aid

> **Matrix shows exact ROI pairs; topology shows graph organization; ring shows group structure; glass brain shows the same graph in anatomy.**

