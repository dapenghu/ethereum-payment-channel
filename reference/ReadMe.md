## Ethereum Payment Channel Reference Implementation
- [STK-smart-contracts](https://github.com/STKtoken/STK-smart-contracts)

    Smart contracts for the STK token payment channel. This repo contains the logic to implement a Payment Channel using ERC20 Tokens. The files contained here are still in development and will be updated in the interests of functionality and security. This is not to be considered the final version. Code related comments or questions can be made in the Issues Section on GitHub. We appreciate your feedback!

- [mattdf/payment-channel](https://github.com/mattdf/payment-channel)

    Ethereum Payment Channel in 50 lines of code

- [postables/Postables-Payment-Channel](https://github.com/postables/Postables-Payment-Channel)

    Postables-Payment-Channel is a collection of easy to use smart contracts that can be used to facilitate payment channels between two parties, while also allowing for what I deem to be "AirDropChannels".

    The payment channels are extremely robust, and allow for payment channels to be made for ANY ERC20 token, or for ethereum itself. These channels allow "micro payments" allowing a party to withdraw "micro" amounts of the channel balance. This is useful in situations where the two parties may want the trust that comes with payment channels, but don't want to end the channel by withdrawing funds from it as is typical with the standard payment channel examples. This can be very useful if you are paying a contractor, and the contractor wants the assurance that all the funds they are being promised actually exist, but you don't want to pay them for work they haven't done yet.

    AirDropChannels are a slightly modified payment channel concept, but instead of one-to-one unidirectional channels, it is a one-to-many unidirectional channel, allowing any number of parties to withdraw tokens from the channel! This can be used to facilitate stupidly cheap airdrops! Gone are the days of airdrops costing the token develop tens of thousands of dollars. One of the benefits to using this method of airdrops, is that unclaimed tokens are refunded back to the token developers wallet as soon as they close the channel! No more wasted money from tokens floating around in unused addresses for ethernity!

    There has been no official audit done of any of the solidity code at all, what so ever. While the logic is sound, and they have been checked with mythril/oyente, please do your own due dilligence before utilizing this code in production environments.

- [WandXDapp/paymentchannel](https://github.com/WandXDapp/paymentchannel)

    Micropayment channel of ERC20 token

- [finalitylabs/set-virtual-channels](https://github.com/finalitylabs/set-virtual-channels)

    Ethereum contracts for simple Set style virtual channels specific to Ether and ERC20 payment hubs

- [BrianPHChen/PaymentChannel](https://github.com/BrianPHChen/PaymentChannel)

    A simple solidity example for payment channel
