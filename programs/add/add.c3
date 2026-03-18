// ==========================================================================
// CoreStation Guest: Add — minimal sub-VM program
// ==========================================================================
//
// Takes an argument count and pointer to an array of u64 values,
// sums all elements, and returns the total.
//
// Signature:  guest_main(argc: ulong, argv: ulong*) -> ulong
//   argc — number of elements in the argv array
//   argv — pointer to an array of ulong values to sum
//
// The return value is the sum of all argv[0..argc-1].
// ==========================================================================
module guest_add;

fn ulong guest_main(ulong argc, ulong* argv) @export("guest_main")
{
  ulong sum;
  for (ulong i; i < argc; i++) {
    sum += argv[i];
  }
  return sum;
}
