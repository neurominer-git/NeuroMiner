# Fractionated decision scores: understanding component contributions

**NeuroMiner 2.0 · Methodological guide**

## What are fractionated decision scores?

A machine-learning model can base a decision on several components of a reduced feature space. **Fractionated decision scores** (abbreviated **Dx**) describe how strongly each component contributes to a particular subject's model decision, and in which direction.

A **positive** component contribution moves the model's decision score towards its positive decision direction; a **negative** contribution moves it in the opposite direction. The interpretation of the positive direction follows the model's target coding. A large contribution indicates influence on the decision score, not necessarily a large effect on clinical risk or a calibrated probability.

Unlike a feature-weight map, which characterizes a model, Dx is **subject-specific**: two subjects evaluated by the same model can have different contributions from the same component.

## How are Dx contributions calculated?

NeuroMiner computes Dx in the **fitted model's input space**, usually the components obtained from dimensionality reduction (such as PCA). The subject's component coordinates, their order, and the trained model must refer to the *same* preprocessing and feature-selection steps. A component score is not the same thing as an original MRI voxel, biomarker, or other raw feature.

Different algorithms require different mathematical decompositions, but the supported implementations share one principle: **for a complete, unfiltered fitted model, component contributions plus a model-specific reference score reconstruct its prediction on an explicitly defined score scale**:

$$
g_m(z_s)=r_m+\sum_{c=1}^{K_m}D_{smc}.
$$

Here $g_m$ is the selected *raw/additive* model score, $r_m$ is an intercept or reference prediction, and $D_{smc}$ is the contribution of component $c$ for subject $s$ under fitted model $m$. The score $g_m$ is not necessarily the final displayed probability or class label. The distinction matters for classification, survival analysis, and ensembles.

### Linear and affine learners: component score × fitted coefficient

For an eligible affine learner, $z_{smc}$ is the subject's value on component $c$ and $w_{mc}$ is the **actual fitted prediction coefficient**, not a feature-importance estimate:

$$
D_{smc}=z_{smc}\,w_{mc},\qquad
 g_m(z_s)=b_m+\sum_c z_{smc}\,w_{mc}.
$$

The reference $r_m=b_m$ is the fitted intercept (zero where the native predictor has no intercept). Where NeuroMiner already supplies a valid coefficient vector, that vector is used directly. Otherwise, the fitted model supplies the exact coefficients, including any required intercept, selected GLMNET regularization-path column, or linear-kernel transformation. **Surrogate visualization weights are not used as Dx coefficients.**

For models evaluated on a positive model-specific normalization scale $a_m$, contributions and the intercept must be scaled consistently:

$$
\widetilde D_{smc}=\frac{D_{smc}}{a_m},\qquad
\frac{g_m(z_s)}{a_m}=\frac{b_m}{a_m}+\sum_c\widetilde D_{smc}.
$$

For a linear SVM, dividing by the Euclidean norm of its coefficient vector gives the geometric-margin scale in that fitted coordinate system. NeuroMiner preserves its established SVM normalization and component-selection conventions. This does **not** turn a margin into a probability, establish cross-fold calibration, or imply that the intercept is available in the displayed Dx matrix.

### Decision trees and ensembles: prediction changes along the path

A tree does not have a single global coefficient for each component. Instead, NeuroMiner decomposes the prediction **along the path actually followed by the subject**, from a reference node to the terminal leaf. If $v_j$ denotes the native score assigned to node $j$, then

$$
D_{smc}=\sum_{j\in\operatorname{path}_m(z_s):\,\operatorname{split}(\operatorname{parent}(j))=c}
\bigl(v_j-v_{\operatorname{parent}(j)}\bigr),
\qquad r_m=v_{\mathrm{root}}.
$$

A component may be used at several split nodes; all of its path changes are added. These changes *telescope*, so the reference score plus all contributions equals the leaf prediction. In a random forest, contributions and reference scores are combined across trees using the ensemble's native averaging or vote-summing rule. Gradient boosting additionally includes its initial prediction and learning-rate-weighted trees.

The decomposition is **exact on the selected score scale**, but its allocation of interaction effects to components depends on the tree structure and node-score convention. It is not a SHAP value, a permutation importance, or a causal effect.

### Dense neural networks: reference-relative layerwise secants

For the supported fitted dense neural networks, NeuroMiner uses a **layerwise secant decomposition** (DeepLIFT-Rescale-style) relative to a fixed reference input $z_0$. The integrated visualization pathway uses the **zero vector in the fitted model coordinates** as its reference. This does not necessarily represent an average or clinically meaningful individual.

For a hidden activation $h$ with pre-activation $u$ and reference activation $u_0$, the local multiplier is

$$
q=\frac{h(u)-h(u_0)}{u-u_0}
$$

(with its derivative limit when $u=u_0$). Multipliers are propagated through the *fitted* weight matrices to obtain an effective subject- and component-specific multiplier $M_{smc}$:

$$
D_{smc}=(z_{smc}-z_{0c})\,M_{smc},\qquad
r_m=g_m(z_0).
$$

This reproduces the raw network output difference, within numerical precision, for the admitted dense architectures. In binary classification it is applied to the **pre-sigmoid logit** or, for the default two-output softmax network, the **difference between the relevant class logits**. The native probability is obtained only *after* reconstructing the raw score. For matLearn's binary MLP, the native prediction interface supplies hard labels rather than an independent numerical logit.

Exact reconstruction is **not** proof that this assignment is uniquely correct: the contributions depend on the reference point, the network representation and the secant attribution convention. Different reference points can yield different Dx profiles for the same unchanged prediction.

### Which algorithm families use which calculation?

The table describes the **verified configurations**, not automatic support for every option of an algorithm with the same name. Some kernel, multiclass, custom-network and feature-transformation variants have no validated Dx contract.

| Algorithm family | Contribution calculation | Raw/additive score and reference | Interpretation / restriction |
|---|---|---|---|
| Linear LIBSVM / LIBLINEAR | Component coordinate × existing primal coefficient | Existing SVM margin convention; legacy normalization may apply | Established Dx branch retained |
| GLMFIT; GLMNET | Exact fitted GLM coefficients; for GLMNET the prediction-active final lambda | Linear predictor / link (identity or logit); fitted intercept | A probability, if provided, is a nonlinear transformation of the logit |
| ELASVM; BAYLIN | Exact fitted affine coefficients | Pre-sigmoid linear score / fitted Bayesian regression score | BAYLIN's classification interface currently exposes a raw predictor, not necessarily a probability |
| Direct, non-kernel BLOREG | Exact fitted sparse coefficients | Raw logit, intercept zero | NeuroMiner's native classification score is a **centred probability**, $\sigma(g)-0.5$; zero coefficients can eliminate PCA maps |
| WBLCOX | Exact fitted coefficients | Log-relative-hazard score; reference zero | Not an event probability; survival-time transforms require additional model information |
| Linear-kernel MikRVM / MVTRVR | Convert relevant fitted dual coefficients into primal component coefficients | Affine score in the original fitted component coordinates | Verified linear-kernel variants only, not general nonlinear kernels |
| matLearn affine regression and classification | Exact fitted `w`/`weights` with the appropriate intercept and admitted options | Regression output or native affine classification score / link | Covers tested L1, L2, least-squares, NB, unregularized Huber, ARD, Student-t (linear), SVM/HSVM/SSVM (linear), logistic, elastic-net logistic and exponential-loss variants; restrictions apply |
| DECTRE; RNDFOR | Root-to-leaf path changes, averaged across trees for RNDFOR | DECTRE: centred class probability; RNDFOR: predicted response or class probability | Contributions depend on fitted split paths and node-score convention |
| GRDBST | Initial boosting score + learning-rate-weighted tree paths | Regression response or binary **raw logit** | Classification probabilities are nonlinear transformations of the additive score |
| matLearn stumps / random forest | Branch/leaf differences or sum of hard tree-vote contributions | Class vote (typically $-1/+1$), vote sum, or constant-leaf regression output | Not automatically a calibrated probability |
| MLPERC; TFDEEP; matLearn MLP | Layerwise secants relative to the zero-input reference | Regression output, binary raw logit, or two-class logit difference | Admitted dense architectures only; attribution is reference-dependent |

Other algorithms or configurations without a verified decomposition should **not** be interpreted as having exact Dx merely because their model provides feature-importance or gradient weights. In particular, support for a feature-weight map is not equivalent to support for fractionated predictions.

### Why a contribution sum may differ from the displayed prediction

The exact identity applies to the **complete contribution vector for one fitted model and its correct reference score, on the correct raw score scale**. Several later operations change what the user sees:

- **Component selection:** Visualization may restrict Dx to components retained by the existing `Fadd` selection. The omitted contributions are not implicitly zero in the full fitted predictor.
- **Probability and other output links:** Sigmoid, softmax, centred-probability, and survival-risk transforms must be applied to the *reconstructed total raw score*, not separately to each component contribution.
- **Cross-validation aggregation:** NeuroMiner aligns components and computes conditional out-of-sample means. Components can have different model coverage; summing their displayed means is generally **not** the ensemble prediction.
- **Reference persistence:** The integrated Dx producer computes a model reference/intercept where supported, but the existing Results Viewer `FracDec_CV2_*` fields do not separately persist every fitted-model reference score. They are component-contribution summaries, not a replacement prediction source.

The established model-prediction output remains authoritative for reported classification, regression and survival predictions.

### A short example across model families

Suppose a fitted model has an additive raw score of **1.4** with a reference score of **0.2**, and two components contribute **+1.7** and **−0.5**. The reconstruction is $0.2+1.7-0.5=1.4$.

- In a **linear model**, the two contributions are component scores multiplied by fitted coefficients.
- In a **tree**, they could be sums of node-to-node changes attributable to the two splitting components.
- In a **neural network**, they could arise from layerwise secant multipliers relative to the chosen input reference.

All three can reconstruct the **same numeric raw score**, but that does not make their attribution conventions interchangeable. If the raw score is a binary logit, a probability would be $\sigma(1.4)$—it is *not* the sum of component-wise probabilities.

## Why do components need to be matched across cross-validation folds?

Components are obtained separately within training partitions. Their number, order and direction can differ across fitted models. To compare them, NeuroMiner matches corresponding component patterns to a shared reference.

A component's axis has an arbitrary orientation. If the component scores change sign, its fitted coefficient changes sign as well. The signed *decision contribution* remains the same:

$$
(-z_{smc})(-w_{mc}) = z_{smc}w_{mc}.
$$

Therefore, aligning a component's visual orientation must not reverse an already calculated Dx contribution. **Matching changes the component identity to which a contribution is assigned, not whether that contribution supports the positive or negative decision direction.**

If several components from the *same model* correspond to one reference component, their signed contributions are **added**:

$$
\widetilde D_{smr}^{\mathrm{group}} =
\sum_{c\in G_{mr}} \widetilde D_{smc}.
$$

For example, contributions of $+2$ and $-5$ group to $-3$, rather than to their mean $-1.5$. This preserves the net effect of those components on the individual model's decision margin.

## How are scores summarized across fitted models?

NeuroMiner uses **out-of-sample evaluation**: a subject's component score is summarized using eligible models in which that subject was evaluated as a cross-validation test case. The summary also conditions on whether the registered component exists in each such model.

For reference component $r$, let $\mathcal E_{sr}$ contain the eligible out-of-sample models with a valid contribution for subject $s$. The displayed mean contribution is

$$
\overline D_{sr}=\frac{1}{|\mathcal E_{sr}|}
\sum_{m\in\mathcal E_{sr}}\widetilde D_{smr}^{\mathrm{group}}.
$$

This is a **conditional mean: the average contribution of a component when it is represented in the subject's eligible models**. It is not the contribution averaged over every fitted model, including those in which the component is absent.

The **number of contributing models** is consequently important when comparing components. Two similar mean contributions can be supported by substantially different numbers of eligible model evaluations.

## Why are some subject–component cells missing?

A component may be present in some training partitions and absent in others. A subject is evaluated only in designated test partitions. As a result, a particular subject may have no out-of-sample model that both evaluates that subject and contains a given reference component.

In that case, NeuroMiner represents the corresponding Dx value as **`NaN` (not available)**, not as zero. This is *structural missingness*: no eligible component contribution was observed. It does not mean that the component had no effect, that the model predicted zero, or that the subject's data were necessarily missing.

The characteristic blocks of missing cells in a subject-by-component heatmap can therefore reflect the interaction of cross-validation membership and component occurrence across folds.

## How should fractionated decision scores be interpreted?

| Observation | Interpretation |
|---|---|
| Large positive Dx | The represented component shifts the subject's decision score towards the model's positive direction. |
| Large negative Dx | The represented component shifts the score towards the negative direction. |
| Dx near zero | The component has little net contribution to that model's decision score on the reported scale. |
| `NaN` | No valid, eligible out-of-sample contribution was available for that subject and component. |
| Similar Dx values with different coverage | Similar conditional strengths, but different amounts of supporting model evidence. |

**Important:** Summing *conditional means* across reference components does not generally reconstruct the final cross-validated ensemble decision score. Different components can be present in different subsets of models, and some ensembles combine fitted-model scores nonlinearly. For all supported algorithm families, additive reconstruction is a **within-model property of the complete, unfiltered decomposition on its specified raw score scale**, including its intercept/reference; it is not a general property of the displayed conditional CV2 means.

## Population profiles: where do components have impact?

The **Population profiles** view summarizes the existing *subject × retained-component* matrix of conditional, out-of-sample mean Dx values. It describes how broadly a component contributes across subjects, how large its contributions tend to be, and how often the sign is positive or negative. It does **not** compute new fitted-model scores or establish predictive, statistical, or causal significance.

For component $c$, let $F_c$ contain the subjects with **finite** mean contributions $\overline D_{sc}$; let $n_c=|F_c|$ and $N$ be the total number of subjects in the displayed matrix. A missing `NaN` cell is excluded from $F_c$; a genuine zero is included.

### Contribution magnitude and concentration

The **mean absolute Dx** measures the typical contribution magnitude among subjects with an available contribution:

$$
A_c = \frac{1}{n_c}\sum_{s\in F_c}|\overline D_{sc}|.
$$

The **effective number of contributing subjects** measures the spread of absolute contributions:

$$
N_{\mathrm{eff},c} = \frac{\left(\sum_{s\in F_c}|\overline D_{sc}|\right)^2}{\sum_{s\in F_c}\overline D_{sc}^{\,2}}.
$$

It is the number of *equally contributing* subjects that would have the same concentration as the observed distribution, **not** the number of subjects with nonzero Dx. For example, contributions `[1, 1, 1, 1]` yield $N_{\mathrm{eff}}=4$, while `[4, 0, 0, 0]` yields $N_{\mathrm{eff}}=1$. Opposite signs do not cancel: `[1, -1, 1, -1]` also yields 4.

To compare components with different numbers of available subjects, the display reports the **normalized concentration score**:

$$
S_c = 1 - \frac{N_{\mathrm{eff},c}}{n_c}.
$$

A score of **0** indicates equal absolute contributions among all finite subjects. Larger scores indicate more unequal, concentrated contributions; the theoretical maximum for $n_c>0$ is $1-1/n_c$, not exactly 1. The score is **undefined** if no subjects have finite Dx, or if all finite Dx values are exactly zero (the ratio becomes $0/0$). Neither case should be displayed as zero concentration. The effective number and concentration depend on the available sample; compare them with $n_c$ and coverage.

**Magnitude and concentration answer different questions.** Multiplying all Dx values of a component by a common positive factor changes $A_c$ but not $S_c$. A component may have high concentration but negligible absolute impact, or substantial absolute impact that is broadly distributed.

### Direction and subject coverage

Among the $n_c$ subjects with finite Dx, the **positive**, **negative**, and **zero** prevalences are, respectively:

$$
P_c^+ = \frac{\#\{s\in F_c:\overline D_{sc}>0\}}{n_c},\quad
P_c^- = \frac{\#\{s\in F_c:\overline D_{sc}<0\}}{n_c},\quad
P_c^0 = \frac{\#\{s\in F_c:\overline D_{sc}=0\}}{n_c}.
$$

These three percentages add to 100% when $n_c>0$. The prevalence of positive and negative contributions refers to the model's signed decision direction, not diagnostic prevalence or clinical risk.

**Subject coverage** is $C_c=n_c/N$. It is the proportion of subjects with an available Dx for that component, **not** the percentage of fitted models representing that component. Those are different denominators. If $n_c=0$, sign percentages and mean absolute Dx are undefined, while subject coverage is zero (assuming $N>0$).

### Reading the population view

The chart displays the first 25 finite values of the selected metric in the current table sort order. The chart metric (concentration, effective N, magnitude, sign prevalence, finite N, or coverage) can be changed independently of the table sorting. The complete component table can be sorted by clicking column headers, and a component can be activated directly from a bar or table row.

Population concentration is **descriptive heterogeneity of model attribution**. It is neither evidence for a distinct biological subtype nor a validated measure of clinical importance. Very low coverage, outliers, and unequal availability across cross-validation folds may all affect concentration. Interpret signs and magnitudes in the context of the original model, component representation, and valid out-of-sample evaluations. The original Model Performance predictions remain authoritative.

## Subject clusters: who has similar contribution profiles?

The **Subject clusters** view groups subjects by their signed, out-of-sample Dx contribution profiles using deterministic **average-linkage hierarchical clustering** and exact optimal leaf ordering. The **contribution space** can be either *Raw signed Dx* or *Relative signed Dx*; **Relative signed Dx is the default for a new panel**. A user may choose a fixed cluster count or ask NeuroMiner to select $k$ from a specified range using one of four descriptive criteria. These are exploratory groups, not established clinical subtypes.

### Clustering space, missingness and distance

**Missingness policy.** Only retained components whose Dx is finite for **every subject in the selected cohort** enter the clustering distance. All subjects are retained, while a component missing for even one subject is excluded *from clustering only*, not from the underlying Dx matrix or the descriptive cluster profiles. At least **two completely covered components** are required. If this is not satisfied, clustering is unavailable and NeuroMiner reports the reason. This policy neither imputes structural missingness as zero nor compares subject distances built from different component subsets. Because it can remove many components, the view reports the admitted component count.

For $n$ subjects and $p$ fully covered components, let $X_{sc}=\overline D_{sc}$ denote the conditional, out-of-sample mean Dx contribution of component $c$ in subject $s$. In **Raw signed Dx** mode, the subject dissimilarity is the root mean squared difference:

$$
d_{st}=\sqrt{\frac{1}{p}\sum_{c=1}^{p}(X_{sc}-X_{tc})^2}.
$$

In **Relative signed Dx** mode, the subject's profile is first normalized by its total absolute contribution across the admitted components:

$$
R_{sc}=\frac{X_{sc}}{\sum_{j=1}^{p}|X_{sj}|},\qquad
d_{st}^{\mathrm{relative}}=\sqrt{\frac{1}{p}\sum_{c=1}^{p}(R_{sc}-R_{tc})^2}.
$$

The relative representation emphasizes the *composition and direction* of a subject's contributions instead of their overall amplitude. The signs are preserved. If a subject's absolute contribution total is zero, this normalization is undefined and clustering in relative mode is not performed; the row is **not** assigned an artificial profile. Raw and relative distances have different interpretations and should not be compared numerically as though they were on the same scale.

The resulting distance matrix defines an average-linkage dendrogram. NeuroMiner determines a deterministic, exact tree-compatible **optimal leaf order** that minimizes the sum of distances between adjacent leaves. Cluster IDs are assigned in this ordered coordinate; they are identifiers, not an ordering of severity or prognosis. A fixed cut produces the requested number of groups.

### Fixed clustering and automatic selection of k

In **Fixed** mode, the cluster-count selector offers **2–8 groups**. In **Auto-select** mode, the user specifies *Min k*, *Max k*, the optimization **criterion**, and—when applicable—the **bootstrap iterations**. Initial Min/Max values are 2 and 8; unlike the fixed selector, the permitted upper limit for auto-selection is the number of available subjects, rather than an arbitrary ceiling of 8. The requested range must satisfy $2\le k_{\min}\le k_{\max}\le n$. A very wide range, especially with bootstrap criteria, can be computationally expensive.

The initial criterion is **Silhouette**. The bootstrap control permits **4–100 iterations** (initial value **16**) for **ARI stability, PAC and consensus cophenetic**; it is disabled for **Silhouette**, which does not use resampling. Editing inputs does not perform an optimization: the user must press **Optimize**. The existing progress viewer reports bootstrap-tree preparation and the currently evaluated $k$.

A single average-linkage tree of the original Dx distance matrix is cut at each integer $k$ in the requested range. For resampling criteria, the algorithm additionally constructs feature-bootstrap trees, described below. Each criterion is evaluated at every candidate $k$ on the same subject set. The optimization plot uses the shared NM2 Cartesian plotting library, with **number of clusters ($k$)** on the horizontal axis, the criterion value on the vertical axis, and the chosen $k$ highlighted. NeuroMiner selects the highest finite score for Silhouette, ARI and Cophenetic, or the lowest finite score for PAC. **Ties favor the smaller k**. Undefined criterion values are not eligible; if no candidate has a finite value, selection fails explicitly. Model predictions, classification errors and clinical outcomes do **not** influence cluster selection.

### Feature-bootstrap stability and consensus clustering

The three resampling criteria use a **feature bootstrap**, not a subject bootstrap. Each of $B$ iterations samples the $p$ fully covered Dx **component columns with replacement**, retaining all $n$ subjects, recomputes the root mean squared distances and fits a new average-linkage tree. The procedure uses a local deterministic random stream (seed **271828**) rather than modifying MATLAB's global random state. The same set of $B$ bootstrap trees is evaluated at each candidate $k$, so changing $k$ does not require redrawing bootstrap samples. This perturbation tests sensitivity to component reweighting; it does **not** assess stability under resampling subjects or independent cohorts.

Let $g_s^{(b,k)}$ denote the group of subject $s$ when bootstrap tree $b$ is cut to $k$ clusters. The **consensus co-clustering matrix** at candidate $k$ is

$$
C_{st}^{(k)}=\frac{1}{B}\sum_{b=1}^{B}
\mathbf{1}\!\left[g_s^{(b,k)}=g_t^{(b,k)}\right].
$$

Each $C_{st}^{(k)}$ is the fraction of bootstrap partitions placing subjects $s$ and $t$ together. Thus $C^{(k)}$ is symmetric, its diagonal equals 1, and all its entries lie between 0 and 1. Values near **1** indicate consistently co-clustered pairs, values near **0** consistently separated pairs, and intermediate values indicate ambiguous assignment under component resampling. These frequencies should **not** be interpreted as posterior probabilities of clinical subtype membership.

The four available criteria are:

- **Silhouette (maximize).** For each subject, $a_s$ is its mean distance to other subjects in its own full-data cluster and $b_s$ the smallest mean distance to another cluster. The criterion is the mean of $(b_s-a_s)/\max(a_s,b_s)$; singleton clusters contribute zero. This uses the **original Dx distances only** and no bootstrap trees.
- **Adjusted Rand index (ARI) stability (maximize).** For each $k$, NeuroMiner compares the full-data cluster partition with each of the $B$ feature-bootstrap partitions using the adjusted Rand index, then averages the defined values. This quantifies partition agreement under component resampling, rather than agreement with an external ground truth.
- **Proportion of ambiguous clustering, PAC (minimize).** Using only distinct unordered subject pairs ($s<t$), the criterion is

  $$
  \mathrm{PAC}(k)=\frac{2}{n(n-1)}\sum_{s<t}
  \mathbf{1}\!\left[0.1<C_{st}^{(k)}<0.9\right].
  $$

  The ambiguity interval is **strictly between** 0.1 and 0.9. Lower PAC indicates fewer ambiguously co-clustered pairs under the specified feature bootstrap.
- **Consensus-tree cophenetic correlation (maximize).** At each $k$, construct the *consensus dissimilarity* $1-C^{(k)}$, with a zero diagonal, then fit an additional average-linkage hierarchy to that dissimilarity. The cophenetic distances from this **consensus-derived tree** are compared with the off-diagonal consensus dissimilarities using their **Pearson correlation**. A higher correlation describes how faithfully this auxiliary hierarchy captures the consensus dissimilarities. The original Dx dendrogram's cophenetic correlation is **not** used to select $k$: that quantity would remain unchanged when the original tree is cut at different cluster counts.

### Reading the selected-k consensus heatmap

When **PAC** or **Consensus cophenetic** is used in Auto-select mode, a **consensus matrix for the winning k** appears beside the optimization curve. It contains the actual $C^{(k)}$ accumulated during scoring; NeuroMiner retains the selected matrix rather than running another bootstrap analysis or constructing a proxy from the final full-data cluster labels. The matrix is not displayed for Silhouette, ARI or fixed-count clustering.

**Rows and columns represent the same subjects, in the optimal leaf order of the original Dx average-linkage dendrogram**, not in the leaf order of the auxiliary consensus tree used by the Cophenetic criterion. A common order makes the consensus pattern comparable with the displayed full-data clusters. The heatmap color scale runs from **0** (rarely or never co-clustered) to **1** (always co-clustered across bootstrap iterations). The axes refer to subject positions in this optimal leaf order; the separate subject table provides the corresponding Case IDs.

For **up to 72 subjects**, each cell shows an individual subject-pair frequency. For **more than 72 subjects**, NeuroMiner partitions the ordered subjects into at most **72 contiguous blocks** and displays the **arithmetic average of all consensus entries** within each block pair. The annotation identifies the result as block-averaged; no individual subject resolution should be inferred from a block. An aggregated diagonal block can be **less than 1**, even though every original individual-subject diagonal entry is 1, because the block average includes off-diagonal pairs. This aggregation is **display-only**: selection statistics and group assignments are computed on the full subject-level matrices.

The consensus heatmap and the **cluster contribution heatmap** describe different objects: the former shows *subject-pair clustering stability*, whereas the latter summarizes *component contributions within the resulting groups*. The cluster contribution heatmap defaults to each cluster's **raw mean signed Dx** for each retained component, regardless of whether clustering used raw or relative distances. Its display selector also offers deviation from the whole-cohort mean and mean absolute Dx. The displayed heatmap ranks 25 components by their greatest between-cluster deviation; all retained components, including those excluded from distance computation, remain available in the expandable **All component profiles** table, with finite counts. Selecting a component uses existing backprojection navigation, while a separate subject table permits navigation to individual Dx profiles.

### Interpretation and limitations of automatic selection

ARI and PAC characterize partition stability **under this particular feature-resampling scheme**; the consensus cophenetic correlation instead measures the fidelity of a hierarchy fitted to the consensus dissimilarities. None establishes optimal clinical taxonomy or generalizability. These criteria can favor different values of $k$. When the optimum is at the search-range boundary, it is the best value **within the tested range**, not evidence of a globally preferred number of clusters. In particular, allowing $k=n$ can make **PAC trivially zero**: every subject is a singleton in every bootstrap partition, so no pair is ambiguously co-clustered. That degeneracy is not evidence for $n$ meaningful subtypes. With few fully covered components, resampling repeatedly draws from a very limited feature set; with few bootstrap iterations, consensus frequencies are coarse (increments of $1/B$). Both can make the apparent stability and preferred cluster count sensitive to configuration. Finally, the selected $k$, consensus matrix and cluster profiles are conditional on the fitted predictive model, the Dx construction, the component-matching and missingness policy, the cohort and the chosen contribution space. Independent-cohort validation is required for claims beyond descriptive exploratory structure.

### Associations with original model performance

The group summary reports group size, number of subjects with evaluable performance, mean original model score/prediction and, where available, the **misclassification percentage** (classification) or **mean absolute prediction error** (regression). These quantities come exclusively from the existing Model Performance extraction and are joined to Dx subjects by canonical **Case ID**. They are not obtained by summing component-wise conditional Dx means. Subjects without an unambiguous matching prediction and observed outcome are excluded from the error summary but retained in the cluster. No model-performance metric participates in constructing the clusters.

Cluster-related performance differences are **post-hoc, descriptive associations** assessed on the same subjects used to discover groups. They do not demonstrate predictive subgroup generalization, statistical significance, or biological mechanism. In particular, the clusters may depend on the fitted model and its cross-validation component-availability patterns; independent-cohort replication and stability analysis would be required before stronger claims.

## Scope and limitations

- **Component presence matters.** A highly influential component that appears in few models is not equivalent to a consistently represented component of the same mean magnitude.
- **Score domains and normalization are model-specific.** SVM margins, logits, probabilities, risk scores, regression outputs and hard votes are not interchangeable units. L2-normalized SVM margins are not calibrated probabilities; native output transformations must be respected.
- **Completeness does not imply uniqueness.** Supported tree and dense-network methods reconstruct the fitted raw model score exactly within numerical tolerance, but interaction allocation follows a path or reference-based convention. Another mathematically complete attribution may differ.
- **Reference scores and component selection matter.** The complete per-model decomposition includes an intercept/reference and all modeled components. Selected, aligned, conditionally averaged results may not reconstruct the displayed ensemble prediction.
- **Component contributions are not causal effects.** Dx describes how the fitted model uses component values. It does not establish that intervening on a component would change the clinical outcome.
- **Algorithm options matter.** Validated affine, tree and dense-network configurations do not imply support for every kernel, multiclass, feature-transformed or custom-architecture variant. Feature importance alone is not an exact Dx decomposition.
- **Early-fusion components can mix modalities.** Their contributions describe shared, potentially multimodal components rather than necessarily modality-specific effects.

**In brief:** Dx describes the signed contribution of a fitted model-input component to an individual's prediction on a defined additive score scale. Linear models use fitted coefficients; trees use changes along decision paths; dense networks use reference-relative secants. The model-level decomposition is complete when all contributions and the reference score are included. The displayed conditional, out-of-sample component means are interpretation summaries—not a substitute for the original predictions. Missing component–subject combinations remain unavailable rather than being assigned zero.
