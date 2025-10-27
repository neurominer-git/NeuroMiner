function [bin_ind, bin_labels] = create_binary_labels(labels, class)

bin_ind = ( labels == class.groups(1) | labels == class.groups(2) );
bin_labels = labels(bin_ind);
ind_pos = bin_labels == class.groups(1); ind_neg = bin_labels == class.groups(2);
bin_labels(ind_pos)=1; bin_labels(ind_neg)=-1;
