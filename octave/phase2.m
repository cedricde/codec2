% phase2.m
% David Rowe Sep 2009
% experiments with phase for sinusoidal codecs, looking at phase
% of excitation with real Am samples from hts1

function phase2(samname, png)
  N = 16000;

  f=45;
  model = load("../src/hts1a_model.txt");
  Wo = model(f,1);
  P=2*pi/Wo;
  L = model(f,2);
  A = model(f,3:(L+2));
  
  phi = zeros(1,L);
  for m=1:L
    phi(m) = -m*Wo*0.3*rand(1,1)*L;
  end
  s = zeros(1,N);

  for m=1:L
    s = s + A(m)*cos(m*Wo*(0:(N-1)) + phi(m));
  endfor

  figure(1);
  clg;
  plot(s(1:250));

  fs=fopen(samname,"wb");
  fwrite(fs,s,"short");
  fclose(fs);

  if (nargin == 2)
      % small image to fit blog

      __gnuplot_set__ terminal png size 450,300
      ss = sprintf("__gnuplot_set__ output \"%s.png\"", samname);
      eval(ss)
      replot;

      % for some reason I need this to stop large plot getting wiped
      __gnuplot_set__ output "/dev/null"
  endif

endfunction

