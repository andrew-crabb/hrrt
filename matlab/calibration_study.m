% Make sure all recordings are by the wall clock, since computer clock can
% be off.
% New phantom placement: Vertical - 230; Horizontal 570; facing backwards
activity=279.0  %uCi
residual=0.00 %uCi
time_activity_to_scan=26.05 %min
time_activity_to_residual=4.0 %min

half_life=109.8 %min for F-18
volume=6510.0 %cc %Used to be 5060.0
activity_t0=activity*2^(-time_activity_to_scan/half_life)
residual_t0=residual*2^(-(time_activity_to_scan-time_activity_to_residual)/half_life)
concentration_Bq_cc=(activity_t0-residual_t0)*37E3/volume
