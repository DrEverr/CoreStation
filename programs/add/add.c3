// ==========================================================================
// CoreStation Guest: Add — minimal sub-VM program
// ==========================================================================
//
// Takes a pointer to an array of u64 values and a count,
// sums all elements, and returns the total.
//
// Signature:  guest_main(argv: char*, argc: ulong) -> ulong
//   argv — pointer to an array of ulong values to sum
//   argc — number of elements in the argv array
//
// The return value is the sum of all argv[0..argc-1].
// ==========================================================================
module guest_add;

fn ulong guest_main(char* argv, ulong argc) @export("guest_main")
{
  ulong* values = (ulong*)argv;
  ulong sum;
  for (ulong i; i < argc; i++) {
    sum += values[i];
  }
  return sum;
}
