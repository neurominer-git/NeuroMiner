# NeuroMiner 2 Results Viewer: relational analysis of tabular-like feature spaces

**Methodological note for the NM2 Results Viewer**  
**Implementation basis:** pre-hackathon NM2 codebase supplied on 2026-09-06 (`NM_4.9995`)  
**Scope:** feature-relation matrices, hierarchical feature clustering, sparsified feature graphs, graph-derived relation patterns, and graph-sparsification robustness.

---

## 1. Purpose and conceptual overview

For tabular-like feature spaces, the NM2 Results Viewer can analyse **relations between input features**, rather than only showing feature-wise model statistics. The starting point is a stored feature-by-feature relation matrix derived during the visualization stage from **preprocessed training-space feature values**.

The most important conceptual distinction is that NM2 contains **two different kinds of grouping**:

1. **Feature clusters** are groups of *features (nodes)* obtained by hierarchical clustering of a correlation-derived dissimilarity matrix. Their main role is to organize/reorder the relation matrix and, optionally, to define contiguous feature groups.
2. **Relation patterns** are groups of *relationships (edges)* obtained from the final sparsified feature graph by hierarchical link-community analysis. They describe irregular network-like patterns of retained pairwise relations and may overlap at the feature level.

These are not alternative names for the same analysis.

### Analysis flow

```text
Stored CV-aggregated relation layers
        |
        v
Stable feature subset + optional feature-level secondary filter
        |
        +------------------------------+
        |                              |
        v                              v
Feature-correlation layer       Selected primary relation layer
        |                              |
Correlation-derived            Graph sparsification
hierarchical clustering               |
        |                              v
Optimal leaf ordering           Final retained graph
        |                              |
Optional cluster extraction            +--> internal graph statistics
        |                              |
Matrix ordering / cluster bands        v
                               Hierarchical link communities
                                      |
                                      v
                                Relation patterns
```

**Pagination and alternative labels are presentation-only.** They do not change the underlying relation matrix, graph edge universe, feature clusters, or relation-pattern membership.

---

## 2. The authoritative relation data

### 2.1 Feature correlation

The principal relation layer is stored as `CorrMat_CV2`. In the Results Viewer it is interpreted as the **CV-aggregated feature-by-feature Pearson correlation matrix of preprocessed training-space feature values**.

For a feature pair \(i,j\), the stored value can be understood schematically as

\[
\bar r_{ij}=\operatorname{mean}_{\mathrm{CV2}}\left(\operatorname{mean}_{\mathrm{CV1}}(r_{ij})\right),
\]

with unavailable/non-estimable values omitted by the visualization generator. The Results Viewer does not re-estimate these correlations from the original data.

Important details:

- The aggregation is an **arithmetic mean of the stored fold/model correlations**; the Results Viewer does not apply a Fisher-\(z\) transformation during display or clustering.
- Non-finite or non-estimable pairs remain unavailable. NM2 does **not** replace them by zero.
- The matrix is validated as symmetric; a single finite triangle can be mirrored, but material asymmetry is treated as a contract violation.
- Feature relations are available only where the visualization backend has stored a valid non-decomposed feature-space relation matrix.

### 2.2 Evidence layers

Two additional pairwise layers may be available:

- `CorrMat_CV2_p_uncorr`: arithmetic mean of \(-\log_{10}(P)\) evidence across CV models.
- `CorrMat_CV2_p_fdr`: arithmetic mean of \(-\log_{10}(q)\) FDR-adjusted evidence across CV models.

The upper triangle is authoritative and is mirrored for display.

These layers must be interpreted carefully. A mean \(-\log_{10}(P)\) or mean \(-\log_{10}(q)\) is an **aggregated evidence descriptor**. It is **not** the P value or q value of the final averaged correlation and should not be interpreted as a formal meta-analytic combined significance test.

For example, a displayed mean FDR-evidence value of 1.301 corresponds numerically to \(-\log_{10}(0.05)\), but it does **not** imply that every CV model had \(q\le0.05\), nor that the averaged correlation itself has a final \(q=0.05\).

### 2.3 Combined early/intermediate-fusion relations

For early- or intermediate-fusion analyses, NM2 can display a persisted **CombinedRelation** containing within- and cross-modality feature relations. The Results Viewer consumes that persisted relation object directly. It does **not** concatenate modality-specific matrices in the browser.

Thus, cross-modality relations shown in a combined feature view are part of the stored scientific result, not a visualization-time reconstruction.

---

## 3. Feature selection occurs before relational structure is derived

The user can first define a stable feature subset and can optionally apply a **secondary feature-level metric filter**. This filter acts on features/nodes, not on individual pairwise edges.

The resulting admissible feature set is then used by both branches of the relational analysis:

- hierarchical feature clustering; and
- graph construction / relation-pattern detection.

This distinction matters because changing the feature universe changes both the clustering problem and the graph topology.

---

# Part I — Hierarchical feature clustering

## 4. What feature clustering is intended to show

Feature clustering asks:

> **Which features are mutually close according to a correlation-derived dissimilarity?**

It is a node/feature clustering method. It is not a graph-community analysis and it is not derived from model importance scores.

NM2 always uses the **feature-correlation layer** for hierarchical feature clustering, even if the matrix/graph is currently displaying an evidence layer.

Two distance definitions are available.

---

## 5. Signed co-variation clustering

For correlation \(r_{ij}\), NM2 defines

\[
d_{ij}=\frac{1-r_{ij}}{2}.
\]

This maps correlation to the interval \([0,1]\):

| Correlation | Distance |
|---:|---:|
| \(r=+1\) | \(d=0\) |
| \(r=0\) | \(d=0.5\) |
| \(r=-1\) | \(d=1\) |

Therefore, **strong positive co-variation produces proximity**, whereas strong negative correlation produces large separation.

Use this mode when the scientific question is whether features tend to vary **in the same direction**.

---

## 6. Absolute-dependency clustering

NM2 alternatively defines

\[
d_{ij}=1-|r_{ij}|.
\]

Here both strong positive and strong negative correlations imply proximity:

| Correlation | Distance |
|---:|---:|
| \(r=+1\) | \(d=0\) |
| \(r=-1\) | \(d=0\) |
| \(r=0\) | \(d=1\) |

Use this mode when the scientific question is whether features are **strongly statistically dependent in a linear sense**, irrespective of direction.

A pair with \(r=+0.9\) and a pair with \(r=-0.9\) are equally close in this mode.

---

## 7. Average-linkage agglomeration

NM2 uses deterministic **average-linkage hierarchical clustering** (UPGMA-style agglomeration).

Initially each feature is its own cluster. At each step NM2 merges the two currently closest clusters. For clusters \(A\) and \(B\), the average-linkage distance is

\[
d(A,B)=\frac{1}{|A||B|}\sum_{i\in A}\sum_{j\in B} d_{ij}.
\]

The implementation updates cluster distances by cluster-size-weighted averaging, which is algebraically equivalent to the expression above.

Consequences:

- clustering reflects the **average separation between two groups**, not the single closest feature pair;
- a cluster does not imply that every within-cluster pair exceeds a fixed correlation threshold;
- the dendrogram merge height is a cluster-level average dissimilarity.

The implementation is deterministic and toolbox-independent. Ties are resolved using stable source feature indices.

---

## 8. Optimal leaf ordering

After constructing the hierarchical tree, NM2 computes an **exact optimal leaf ordering** compatible with that tree.

Among all left/right orientations allowed by the fixed hierarchical tree, NM2 selects the feature order \(\pi\) minimizing

\[
J(\pi)=\sum_{t=1}^{n-1} d_{\pi_t,\pi_{t+1}}.
\]

In practical terms, features that are close under the selected dissimilarity are placed next to one another as much as the dendrogram permits. This makes block structure easier to see in the relation matrix.

**Optimal leaf ordering changes only the display order. It does not change the hierarchical tree or the cluster memberships.**

---

## 9. Optional extraction of explicit feature clusters

Hierarchical clustering can be used solely for ordering, or the dendrogram can be cut to produce explicit feature groups.

### 9.1 Fixed cluster count

If the user requests \(K\) clusters, NM2 retains the first

\[
n-K
\]

agglomerative merges and treats the resulting connected branches as the \(K\) feature clusters.

This is a **forced partition**. Choosing \(K=4\) does not mean that the data provide evidence that four is the uniquely correct number of clusters.

### 9.2 Cut height

Alternatively the user can specify a dissimilarity cut height \(h\in[0,1]\). All dendrogram merges with linkage height \(\le h\) are retained.

For individual feature pairs, the distance definitions provide an intuitive scale. For example:

- signed mode: \(h=0.25\) corresponds pairwise to \(r=0.5\);
- absolute mode: \(h=0.25\) corresponds pairwise to \(|r|=0.75\).

However, once clusters contain multiple features, the linkage height is an **average inter-cluster distance**. A cut height must therefore **not** be interpreted as a minimum correlation that every pair inside a cluster satisfies.

### 9.3 Cluster numbering

Cluster IDs are normalized according to the deterministic leaf order. They are convenient labels for one particular clustering state, not immutable biological identities.

---

## 10. Conditions under which clustering is disabled

NM2 deliberately refuses to fabricate a clustering solution when the correlation dissimilarity is not complete.

Hierarchical feature clustering requires:

- at least two admissible features;
- no more than 500 admissible features per request;
- a finite valid correlation for every off-diagonal pair in the selected feature subset.

If pairwise correlations are unavailable, NM2 does **not** impute them and does not replace them by zero.

---

# Part II — Feature graphs

## 11. From a dense relation matrix to a sparse graph

A complete relation matrix contains up to

\[
\frac{n(n-1)}{2}
\]

undirected feature pairs. For moderate numbers of features this is already too dense to interpret as a network. NM2 therefore constructs a **sparsified graph**.

- **Nodes:** admissible features.
- **Candidate edges:** valid, finite, non-zero off-diagonal pairs from the selected primary relation layer.
- **Edge source:** the currently selected physical relation layer: feature correlation, mean \(-\log_{10}(P)\), or mean \(-\log_{10}(q)\), when available.

The graph is constructed **before** relation patterns are identified. Relation-pattern analysis never adds an edge that was not retained by graph construction.

---

## 12. Graph sparsification modes

### 12.1 Legacy strongest-edge union

The default compatibility mode retains the union of:

1. the strongest \(K\) admissible incident edges for each feature; and
2. the strongest \(G\) admissible edges globally.

Current defaults are:

- \(K=5\) per node;
- \(G=250\) globally.

“Strongest” means descending **absolute magnitude of the selected relation layer**, with stable feature-index tie breaking.

This rule helps prevent less-connected features from disappearing solely because a small set of very strong global relationships dominates the matrix.

### 12.2 Fixed density

For \(n\) nodes and requested density \(\rho\), the requested edge count is

\[
M_{\mathrm{req}}=\operatorname{round}\left(\rho\frac{n(n-1)}{2}\right).
\]

NM2 retains exactly that many strongest candidate edges when possible. If fewer valid non-zero candidates exist, the realized graph is candidate-limited and this is reported explicitly.

### 12.3 Absolute threshold

NM2 retains every candidate edge satisfying

\[
|w_{ij}|\ge \tau,
\]

where \(w_{ij}\) is the value in the selected primary relation layer.

For correlation this is an absolute correlation threshold. For a non-negative evidence layer, it is simply a threshold on that evidence value.

Again, thresholding a mean \(-\log_{10}(P)\) or mean \(-\log_{10}(q)\) layer should be interpreted as thresholding the stored **CV-aggregated evidence descriptor**, not as a conventional significance test on the final mean correlation.

---

## 13. Internal graph statistics

After sparsification, NM2 attaches the aligned correlation and evidence values to every retained edge. The backend then computes graph statistics using **absolute correlation as the affinity**, even when the graph edge universe was selected using a different physical layer. These statistics support graph inspection, node ranking, and the fixed-density robustness analysis. **They are not currently exposed as a dedicated graph-statistics data export and should not be presented as an exported NM2 result product.**

For feature \(i\), the internal graph contract can contain quantities including:

- degree;
- absolute strength \(\sum_j |r_{ij}|\);
- positive correlation strength \(\sum_j \max(r_{ij},0)\);
- negative correlation strength \(\sum_j |\min(r_{ij},0)|\);
- weighted betweenness centrality;
- harmonic closeness;
- eigenvector centrality;
- connected-component membership.

Weighted shortest paths use

\[
\ell_{ij}=\frac{1}{|r_{ij}|+10^{-12}}.
\]

Thus stronger absolute correlations correspond to shorter graph distances.

The four graph-topological quantities below answer **different questions about the position of a feature in the sparsified graph**.

### 13.1 Weighted betweenness centrality — “Is this feature a bridge?”

Betweenness centrality measures how often a node lies on shortest paths **between other nodes**. In NM2, shortest paths are weighted by the inverse of absolute correlation strength, so routes preferentially pass through strong retained feature-feature relations.

A simple schematic is:

```text
A — B — C — X — D — E — F
              ^
           bridge
```

Feature `X` may have only a modest number of direct connections, but if many of the strongest/shortest routes linking the left-hand and right-hand parts of the graph must pass through it, its weighted betweenness is high.

Conceptually:

> **High weighted betweenness identifies connector features that link otherwise more separated parts of the retained relation network.**

This should not be interpreted as causal mediation or predictive importance. It is a property of the current sparsified graph.

### 13.2 Harmonic closeness — “How centrally located is this feature?”

Harmonic closeness asks how easily a node can reach the other nodes through short weighted paths. It is based on reciprocal shortest-path distances:

\[
C_H(i) \propto \sum_{j\ne i}\frac{1}{d(i,j)},
\]

where \(d(i,j)\) is the weighted shortest-path distance between features \(i\) and \(j\).

A node has high harmonic closeness when many other features can be reached through only a small amount of graph distance:

```text
        B
        |
    C — A — D
        |
        E
```

If `A` is only a few strong connections away from much of the network, it has high harmonic closeness.

The distinction from betweenness is important:

- **betweenness:** do routes **between other features** pass through this feature?
- **closeness:** how **near is this feature to the rest of the graph**?

The harmonic formulation is useful for sparse graphs because disconnected nodes contribute zero rather than making the measure undefined.

### 13.3 Eigenvector centrality — “Is this feature connected to other central features?”

Eigenvector centrality implements a recursive concept of network prominence:

> A connection to a highly connected/central node contributes more than a connection to a peripheral node.

For example:

```text
        B
        |
    C — A — D
        |
        E
```

If `B`, `C`, `D`, and `E` are themselves strongly embedded in a highly interconnected region of the graph, `A` receives high eigenvector centrality.

A feature can therefore have relatively few direct links yet still obtain high eigenvector centrality if those links lead to features that are themselves central.

In NM2, the graph-statistics affinity is based on **absolute correlation**, so strong positive and strong negative retained correlations both contribute to this notion of network prominence.

Conceptually:

> **High eigenvector centrality identifies features embedded in a strongly interconnected network core.**

Again, this is not a feature-importance score for the prediction model.

### 13.4 Connected-component membership — “Which graph island does this feature belong to?”

Connected-component membership is fundamentally different from the three centrality measures above. It is **categorical**, not a continuous score.

A connected component is a maximal set of nodes in which every feature can be reached from every other feature through some path of retained edges:

```text
A — B — C       D — E — F       G
component 1     component 2    component 3
```

Here:

- `A`, `B`, `C` belong to component 1;
- `D`, `E`, `F` belong to component 2;
- isolated feature `G` forms its own component.

Connected components therefore identify **disconnected islands of the sparsified relation graph**.

Component membership can change substantially when graph sparsification changes: removing a small number of bridging edges may split one large component into several smaller components.

### 13.5 Practical distinction

A useful shorthand for participants is:

> **Betweenness finds bridges; harmonic closeness finds centrally located features; eigenvector centrality finds features embedded in an influential network core; connected components identify disconnected islands of the graph.**

These quantities are all properties of the **sparsified graph**, not of the original dense correlation matrix in isolation. Consequently, changing the graph-pruning rule or density can alter all of them. This is one reason NM2's fixed-density robustness analysis evaluates graph structure across several sparsification levels.

These graph statistics describe **topological position within the sparsified feature-relation graph**. They are **not measures of predictive feature importance**, model coefficients, causal influence, or feature relevance to the target variable. For the hackathon, they are best understood as internal/diagnostic quantities supporting graph characterization and robustness, not as standalone exportable scientific endpoints.

---

# Part III — Relation patterns: edge communities

## 14. What a relation pattern means

Relation patterns answer a different question from feature clustering:

> **Which retained pairwise relationships participate in similar local network neighbourhoods?**

NM2 uses **hierarchical link communities**. The clustering objects are graph **edges**, not feature nodes.

This has an important consequence: because edges are clustered, a single feature can participate in **multiple relation patterns** through different incident edges. Relation patterns can therefore overlap in their node/feature membership even though each retained edge has one pattern assignment at the selected cut.

This is why relation patterns appear as potentially irregular silhouettes on the relation matrix rather than as simple square diagonal blocks.

---

## 15. Relation patterns are derived from the final pruned graph

The relation-pattern analysis uses exactly the graph produced by the selected primary relation layer and graph-sparsification rule.

Therefore a relation pattern depends on:

- the admissible feature set;
- the selected primary relation layer;
- the graph-pruning mode and its parameters;
- the resulting retained edge universe.

Changing any of these can change the patterns. NM2 consequently treats pattern IDs as **local to the current graph identity** and resets the selected pattern when graph construction changes.

There is no separate hidden correlation-only pattern graph.

---

## 16. Jaccard similarity between adjacent edges

Consider two graph edges sharing one feature \(k\):

\[
e_{ik}=(i,k),\qquad e_{jk}=(j,k).
\]

For each non-shared endpoint, NM2 constructs its **inclusive neighbourhood**

\[
N_+(i)=\{i\}\cup N(i),
\]

where \(N(i)\) is the set of graph neighbours of \(i\).

The similarity between the two adjacent edges is the Jaccard similarity

\[
S(e_{ik},e_{jk})=
\frac{|N_+(i)\cap N_+(j)|}
{|N_+(i)\cup N_+(j)|}.
\]

Only edge pairs that share an endpoint contribute to the link-similarity hierarchy.

### Methodological implication

Once the graph has been pruned, **relation-pattern similarity uses graph topology, not edge magnitude or correlation sign**. Edge weights influence patterns indirectly because they determine which edges survive sparsification, but the Jaccard link-community step itself uses the neighbourhood structure of the retained graph.

Consequently, positively and negatively correlated edges can occur in the same relation pattern if they participate in the same local graph topology.

---

## 17. Hierarchical link-community construction

NM2 sorts adjacent edge pairs from highest to lowest Jaccard similarity and progressively joins edge sets as the similarity threshold is lowered. This creates a deterministic hierarchical family of edge communities, equivalent to thresholding a single-linkage hierarchy on link similarity.

Two cut strategies are available.

### 17.1 Automatic cut: maximum partition density

The default mode chooses the link-similarity cut that maximizes **partition density**.

For one edge community \(c\) with

- \(m_c\) edges and
- \(n_c\) distinct nodes,

the community density used by NM2 is

\[
D_c=
\frac{2(m_c-n_c+1)}{(n_c-2)(n_c-1)}
\qquad (n_c>2).
\]

Communities with insufficient nodes/edges contribute zero.

The global partition density is the edge-count-weighted average

\[
D=\frac{1}{M}\sum_c m_c D_c,
\]

where \(M\) is the total number of retained graph edges.

Intuitively:

- a tree-like community has little or no excess connectivity and therefore low partition density;
- a densely interconnected community has higher partition density;
- a triangle has maximal local density under this normalization.

NM2 evaluates the hierarchy and retains the cut with the highest partition density. Deterministic tie handling preserves reproducibility.

### 17.2 Manual Jaccard-similarity cut

The user can instead choose a threshold \(s\in[0,1]\). Adjacent edge pairs with

\[
S\ge s
\]

are joined transitively into edge communities.

Higher thresholds require more similar local neighbourhoods and generally produce smaller/more fragmented edge communities. Lower thresholds permit broader patterns.

---

## 18. Minimum relation-pattern size

The default minimum is **two retained edges** per selectable relation pattern.

Communities smaller than the selected minimum are assigned pattern ID 0 and shown as **unclustered edges** rather than being presented as substantive multi-edge patterns.

Because relation patterns are graph-local, “Pattern 1” in one graph is not assumed to correspond to “Pattern 1” after changing density, threshold, feature filtering, or relation layer.

---

# Part IV — Why feature clusters and relation patterns can disagree

## 19. They encode different structure

It is scientifically legitimate—and often informative—for feature clusters and relation patterns not to coincide.

### Feature clustering

- clusters **features**;
- always uses the Pearson-correlation layer;
- uses correlation magnitude and sign through one of two explicit distance functions;
- is based on average-linkage distances across all selected feature pairs;
- produces a tree and optionally a non-overlapping feature partition.

### Relation patterns

- cluster **retained graph edges**;
- use whichever physical relation layer defined the graph edge universe;
- are calculated only after graph sparsification;
- use Jaccard similarity of local graph neighbourhoods;
- can overlap at the feature/node level.

A useful shorthand is:

> **Feature clusters describe blocks of mutually related variables; relation patterns describe network motifs of selected relationships.**

The first tends to appear as contiguous block structure after matrix reordering. The second can trace irregular, overlapping structures across those blocks.

---

# Part V — Automated graph-sparsification robustness

## 20. “Identify robust structure” does not test sampling robustness

For fixed-density graphs, NM2 provides a deterministic sensitivity analysis intended to answer:

> **Is the graph topology reasonably stable across nearby sparsification densities?**

This is a graph-construction sensitivity analysis. It does **not** assess test-retest reliability, bootstrap stability, CV reproducibility, statistical significance, causal stability, or predictive feature importance.

### 20.1 Density grid

By default NM2 evaluates fixed-density graphs at:

\[
5\%,\ 7.5\%,\ 10\%,\ 12.5\%,\ 15\%,\ 20\%,\ 25\%,\ 30\%.
\]

Duplicate realized edge counts are removed. At least five admissible features and at least three distinct graph structures are required.

### 20.2 Centrality-rank concordance

For each pair of adjacent density settings, NM2 computes tie-aware Spearman rank concordance for:

- degree;
- absolute correlation strength;
- betweenness;
- harmonic closeness;
- eigenvector centrality.

The finite correlations are averaged to obtain a centrality-concordance score.

### 20.3 Topology similarity

NM2 also compares:

- connected-node fraction;
- largest-component fraction;
- component count.

Their normalized similarities are averaged.

### 20.4 Composite stability score

The score is

\[
S_{\mathrm{stable}}
=0.75\,S_{\mathrm{centrality}}
+0.25\,S_{\mathrm{topology}}.
\]

A setting is eligible when all of the following hold:

- stability score \(\ge0.82\);
- connected-node fraction \(\ge0.80\);
- largest-component fraction \(\ge0.75\);
- requested density was not candidate-limited;
- graph statistics are available.

At least **three consecutive eligible settings** are required to form a stable plateau.

NM2 selects the **longest eligible plateau**; ties are resolved by higher mean stability and then lower starting density. The representative graph is the **sparsest density in the selected plateau**.

After that density is applied, relation patterns are recomputed from the newly pruned graph.

---

# Part VI — Practical interpretation for hackathon participants

## 21. A 60-second explanation

A concise explanation of the relational tools is:

> NM2 first stores a cross-validated correlation structure between preprocessed training features. The matrix can be reordered by hierarchical clustering. In signed mode, positively co-varying features are placed together; in absolute-dependency mode, strong positive and negative relations are both considered close. The clustering uses average linkage, and the final matrix order is optimized so related features sit next to each other.
>
> The graph view answers a different question. NM2 first keeps only a reproducible subset of the strongest or threshold-passing relationships. It then looks for *communities of edges* whose endpoints have similar local neighbourhoods. These are the relation patterns. Because the edges rather than the features are clustered, one feature can participate in several patterns. The patterns therefore reveal network-like relational structure that need not match the block-like feature clusters.

---

## 22. Which clustering mode should participants choose?

### Signed co-variation

Prefer when:

- the direction of association is scientifically meaningful;
- positively co-varying features should cluster together;
- anticorrelated features should be separated.

### Absolute dependency

Prefer when:

- the main question is redundancy/dependence irrespective of sign;
- strongly anticorrelated features should be considered closely related;
- one is exploring tightly coupled but oppositely directed variables.

For exploratory work, comparing both is often more informative than treating one as universally correct.

---

## 23. How to think about graph density

A graph with too many edges approaches the complete correlation matrix and becomes visually/topologically uninformative. A graph with too few edges can fragment and make patterns unstable.

Therefore:

1. use the default strongest-edge union for a quick descriptive overview;
2. use fixed density when comparing graphs across analyses/settings, because it controls edge count explicitly;
3. use **Identify robust structure** when you want a principled sensitivity check across a predefined density range;
4. interpret relation patterns only in the context of the graph-sparsification rule that generated them.

---

# Part VII — Methodological cautions

## 24. What these analyses do **not** establish

The relational tools are descriptive/exploratory analyses of the model-specific preprocessed training feature space. They do not by themselves establish:

- causal relationships between features;
- predictive importance of a feature for the model target;
- an independently replicated network;
- statistical significance of a feature cluster or relation pattern;
- uniqueness of the selected number of feature clusters;
- sampling stability of a relation pattern;
- biological validity of a graph community.

### Specific cautions

1. **CV averaging is not external validation.** Averaging pairwise relations across CV models reduces dependence on a single fold but does not create an independent replication sample.
2. **Mean evidence is not a final combined hypothesis test.** Mean \(-\log_{10}(P)\) and mean \(-\log_{10}(q)\) should be treated as descriptive CV-aggregated evidence layers.
3. **Feature clusters are parameter-dependent.** Signed versus absolute distance and the dendrogram cut can materially change the result.
4. **Relation patterns are sparsification-dependent.** Their edge universe changes when graph density, threshold, layer, or feature selection changes.
5. **Pattern IDs are local.** Numeric IDs should not be matched across graphs as though they were persistent biological entities.
6. **Centrality is graph topology, not model salience.** A highly central feature is not necessarily highly predictive; the centrality measures are internal graph-characterization quantities rather than standalone exported outputs.
7. **Absolute-dependency clustering loses sign by design.** A positive and a negative correlation of equal magnitude are treated as equally close.
8. **Link communities are topological after pruning.** Correlation magnitude/sign are not used directly by the Jaccard community step once the graph edge set is fixed.

---

# Part VIII — Suggested Methods text for reports/publications

## 25. Feature-relation matrix and hierarchical clustering

> Pairwise relations between preprocessed training-space features were summarized using the NeuroMiner 2 visualization-stage feature-relation matrices. Pearson correlations were aggregated arithmetically across cross-validation models/partitions, with non-estimable pairs retained as unavailable. For visualization, features were hierarchically clustered using deterministic average linkage. Dissimilarity was defined either as \(d=(1-r)/2\) for signed co-variation or as \(d=1-|r|\) for absolute dependency. The resulting tree was displayed using an exact optimal leaf ordering that minimized the sum of dissimilarities between adjacent leaves while preserving the hierarchical topology. Where explicit feature groups were requested, the tree was cut either to a predefined number of clusters or at a predefined linkage height.

## 26. Feature graph and relation-pattern analysis

> A sparse feature-relation graph was constructed from the selected relation layer after feature-level filtering. Edges were retained using either a strongest-edge union rule, a fixed graph density, or an absolute relation threshold. Relation patterns were subsequently identified from the exact retained graph by hierarchical link-community analysis. Similarity between adjacent edges sharing a node was defined as the Jaccard overlap between the inclusive neighbourhoods of their non-shared endpoints. The automatic community cut maximized link-community partition density; alternatively, a prespecified Jaccard-similarity threshold was used. Communities containing fewer than the configured minimum number of edges were treated as unclustered. Because communities were defined over edges, individual features could participate in more than one relation pattern.

## 27. Graph-sparsification robustness

> For fixed-density graphs, sparsification sensitivity was assessed over a predefined density grid. Adjacent densities were compared using tie-aware Spearman concordance of node centrality rankings and similarity of global connectivity summaries. A composite stability score weighted centrality concordance by 0.75 and topology similarity by 0.25. Stable plateaus required at least three consecutive eligible density settings satisfying prespecified stability and connectivity criteria; the sparsest graph within the selected plateau was used as the representative structure. This procedure assesses sensitivity to graph sparsification and is not a measure of sampling reliability or statistical significance.

---

# Part IX — Implementation anchors in NM2

The methodological behavior described above is implemented in three main backend authorities:

- `core/NMResultsViewerFeatureRelationTools.m`  
  Relation-matrix normalization, feature filtering, relation-view construction, correlation-derived clustering, cluster extraction, common matrix ordering, and projection of relation patterns onto matrix views.

- `core/NMHierarchicalClusteringTools.m`  
  Toolbox-independent deterministic average-linkage agglomeration and exact optimal leaf ordering.

- `core/NMResultsViewerFeatureGraphTools.m`  
  Graph sparsification, pairwise evidence attachment, connected components, graph statistics, hierarchical link communities, partition-density optimization, and fixed-density robustness analysis.

The browser UI consumes these backend contracts and does not independently infer scientific clustering or graph structure.

---

# References

1. Ahn YY, Bagrow JP, Lehmann S. **Link communities reveal multiscale complexity in networks.** *Nature*. 2010;466:761-764. doi:10.1038/nature09182.
2. Bar-Joseph Z, Gifford DK, Jaakkola TS. **Fast optimal leaf ordering for hierarchical clustering.** *Bioinformatics*. 2001;17(Suppl 1):S22-S29. doi:10.1093/bioinformatics/17.suppl_1.S22.
3. Sokal RR, Michener CD. **A statistical method for evaluating systematic relationships.** *University of Kansas Science Bulletin*. 1958;38:1409-1438.

---

## One-line distinction to remember

> **Feature clustering groups variables using correlation-derived distance; relation-pattern analysis groups retained relationships using graph-neighbourhood similarity.**
